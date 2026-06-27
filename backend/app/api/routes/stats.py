from fastapi import APIRouter, HTTPException, Query
from datetime import datetime, timedelta
import asyncpg
import csv
from io import StringIO
from fastapi import Response
from app.core.config import settings


router = APIRouter()

@router.get("/stats")
async def get_stats(
    periode: str = Query("30j", description="7j, 30j, 90j, 365j"),
    parcelle_id: int | None = Query(None),
    maladie: str | None = Query(None),
    user_id: int = Query(1)
):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        jours = {"7j": 7, "30j": 30, "90j": 90, "365j": 365}.get(periode, 30)
        
        # ✅ Calculer la date de début en Python
        date_debut = datetime.now() - timedelta(days=jours)
        
        # Filtres pour les observations
        obs_filters = [
            "o.timestamp >= $1",  # ← Maintenant un paramètre datetime
            "d.id_utilisateur = $2"
        ]
        params = [date_debut, user_id]
        param_index = 3
        
        if parcelle_id:
            obs_filters.append(f"o.id_parcelle = ${param_index}")
            params.append(parcelle_id)
            param_index += 1
        if maladie:
            obs_filters.append(f"o.maladie_nom = ${param_index}")
            params.append(maladie)
            param_index += 1
        
        where_clause = " AND ".join(obs_filters)
        
        # 1. Total diagnostics
        total_diag = await conn.fetchval(f"""
            SELECT COUNT(DISTINCT d.id_diagnostic)
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)
        
        # 2. Total zones
        total_zones = await conn.fetchval("""
            SELECT COUNT(DISTINCT z.id_zone)
            FROM zone_infectee z
            LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            WHERE z.id_utilisateur = $1
        """, user_id)
        
        # 3. Total parcelles
        total_parcelles = await conn.fetchval("""
            SELECT COUNT(*) FROM parcelle WHERE id_utilisateur = $1
        """, user_id)
        
        # 4. Taux infection moyen
        taux_moyen = await conn.fetchval(f"""
            SELECT 
                CASE WHEN COUNT(*) > 0 
                THEN SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
                ELSE 0 END
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)
        
        # 5. Répartition par maladie
        repartition = await conn.fetch(f"""
            SELECT 
                CASE 
                    WHEN o.maladie_nom = 'Tomato_healthy' THEN 'Sain'
                    WHEN o.maladie_nom = 'Tomato_Early_Blight' THEN 'Alternariose'
                    WHEN o.maladie_nom = 'Tomato_Late_blight' THEN 'Mildiou'
                    WHEN o.maladie_nom = 'Tomato_leaf_yellow_curl_virus' THEN 'Virus jaune'
                    WHEN o.maladie_nom = 'Tomato_mold' THEN 'Moisissure'
                    WHEN o.maladie_nom = 'Tomato_Septoria_leaf_spot' THEN 'Septoriose'
                    ELSE COALESCE(o.maladie_nom, 'Inconnue')
                END as nom,
                COUNT(*) as count,
                ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pourcentage
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
            GROUP BY o.maladie_nom
            ORDER BY count DESC
        """, *params)
        
        # 6. Top zones
        if maladie:
            top_zones = await conn.fetch(f"""
                WITH zone_counts AS (
                    SELECT 
                        z.id_zone,
                        z.nombre_observations,
                        COALESCE(p.nom, 'Hors parcelle') as parcelle_nom,
                        COUNT(o.id_observation) as maladie_count
                    FROM zone_infectee z
                    LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
                    LEFT JOIN observation o ON ST_DWithin(
                        ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                        ST_SetSRID(ST_MakePoint(z.centre_longitude, z.centre_latitude), 4326)::geography,
                        z.rayon
                    )
                    LEFT JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                    WHERE z.id_utilisateur = $1 AND o.maladie_nom = $2
                    GROUP BY z.id_zone, z.nombre_observations, p.nom
                )
                SELECT id_zone, nombre_observations, parcelle_nom, maladie_count
                FROM zone_counts
                ORDER BY maladie_count DESC
                LIMIT 5
            """, user_id, maladie)
            top_zones_clean = [{
                "id_zone": z["id_zone"],
                "nombre_observations": z["maladie_count"],
                "parcelle_nom": z["parcelle_nom"]
            } for z in top_zones]
        else:
            top_zones = await conn.fetch("""
                SELECT 
                    z.id_zone,
                    z.nombre_observations,
                    COALESCE(p.nom, 'Hors parcelle') as parcelle_nom
                FROM zone_infectee z
                LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
                WHERE z.id_utilisateur = $1
                ORDER BY z.nombre_observations DESC
                LIMIT 5
            """, user_id)
            top_zones_clean = [{
                "id_zone": z["id_zone"],
                "nombre_observations": z["nombre_observations"],
                "parcelle_nom": z["parcelle_nom"]
            } for z in top_zones]
        
        # 7. Top parcelles
        if maladie:
            top_parcelles = await conn.fetch(f"""
                SELECT 
                    p.id_parcelle,
                    p.nom,
                    COUNT(o.id_observation) as total_observations,
                    SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) as observations_malades,
                    ROUND(SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) * 100.0 / COUNT(o.id_observation), 1) as taux_infection
                FROM parcelle p
                JOIN observation o ON o.id_parcelle = p.id_parcelle
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE p.id_utilisateur = $1 AND o.maladie_nom = $2
                GROUP BY p.id_parcelle, p.nom
                ORDER BY COUNT(o.id_observation) DESC
                LIMIT 5
            """, user_id, maladie)
        elif parcelle_id:
            top_parcelles = await conn.fetch("""
                SELECT 
                    p.id_parcelle,
                    p.nom,
                    COUNT(o.id_observation) as total_observations,
                    SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) as observations_malades,
                    ROUND(SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) * 100.0 / COUNT(o.id_observation), 1) as taux_infection
                FROM parcelle p
                JOIN observation o ON o.id_parcelle = p.id_parcelle
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE p.id_utilisateur = $1 AND p.id_parcelle = $2
                GROUP BY p.id_parcelle, p.nom
                LIMIT 5
            """, user_id, parcelle_id)
        else:
            top_parcelles = await conn.fetch("""
                SELECT 
                    p.id_parcelle,
                    p.nom,
                    COUNT(o.id_observation) as total_observations,
                    SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) as observations_malades,
                    ROUND(SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) * 100.0 / COUNT(o.id_observation), 1) as taux_infection
                FROM parcelle p
                JOIN observation o ON o.id_parcelle = p.id_parcelle
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE p.id_utilisateur = $1
                GROUP BY p.id_parcelle, p.nom
                ORDER BY taux_infection DESC
                LIMIT 5
            """, user_id)
        
        repartition_clean = [{"nom": r["nom"], "count": r["count"], "pourcentage": r["pourcentage"]} for r in repartition if r["nom"] and r["nom"] != "Inconnue"]
        
        return {
            "total_diagnostics": total_diag or 0,
            "total_zones": total_zones or 0,
            "total_parcelles": total_parcelles or 0,
            "taux_infection_moyen": round(taux_moyen or 0, 1),
            "repartition_maladies": repartition_clean,
            "top_zones": top_zones_clean,
            "top_parcelles": [dict(p) for p in top_parcelles]
        }
    except Exception as e:
        print(f"Erreur dans /stats: {e}")
        raise
    finally:
        await conn.close()


@router.get("/stats/zone/{id_zone}")
async def get_zone_detail(id_zone: int, user_id: int = Query(1)):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Requête pour récupérer la zone
        zone_query = """
            SELECT 
                z.id_zone,
                z.centre_latitude,
                z.centre_longitude,
                z.nombre_observations,
                z.zone_type,
                z.id_parcelle,
                z.rayon,
                COALESCE(p.nom, 'Hors parcelle') as parcelle_nom
            FROM zone_infectee z
            LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            WHERE z.id_zone = $1 AND z.id_utilisateur = $2
        """
        
        zone = await conn.fetchrow(zone_query, id_zone, user_id)
        
        if not zone:
            return {"error": "Zone non trouvee"}
        
        # Utiliser le rayon de la zone (minimum 3.0m)
        rayon_recherche = max(zone["rayon"], 3.0)
        print(f"🔍 Zone #{id_zone}: rayon zone={zone['rayon']}m, recherche={rayon_recherche}m")
        
        # Requête pour récupérer les maladies
        maladies_query = """
            SELECT 
                CASE 
                    WHEN o.maladie_nom = 'Tomato_healthy' THEN 'Sain'
                    WHEN o.maladie_nom = 'Tomato_Early_Blight' THEN 'Alternariose'
                    WHEN o.maladie_nom = 'Tomato_Late_blight' THEN 'Mildiou'
                    WHEN o.maladie_nom = 'Tomato_leaf_yellow_curl_virus' THEN 'Virus jaune'
                    WHEN o.maladie_nom = 'Tomato_mold' THEN 'Moisissure'
                    WHEN o.maladie_nom = 'Tomato_Septoria_leaf_spot' THEN 'Septoriose'
                    ELSE COALESCE(o.maladie_nom, 'Inconnue')
                END as nom,
                COUNT(*) as count,
                ROUND(COUNT(*) * 100.0 / $1, 1) as pourcentage
            FROM observation o
            JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
            WHERE ST_DWithin(
                ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography,
                $4
            )
            AND d.id_utilisateur = $5
            GROUP BY o.maladie_nom
            ORDER BY count DESC
        """
        
        maladies = await conn.fetch(
            maladies_query,
            zone["nombre_observations"],
            zone["centre_longitude"],
            zone["centre_latitude"],
            rayon_recherche,
            user_id
        )
        
        # Si aucune maladie trouvée, vérifier les observations
        if not maladies:
            obs_count_query = """
                SELECT COUNT(*)
                FROM observation o
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE ST_DWithin(
                    ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                    $3
                )
                AND d.id_utilisateur = $4
            """
            obs_count = await conn.fetchval(
                obs_count_query,
                zone["centre_longitude"],
                zone["centre_latitude"],
                rayon_recherche,
                user_id
            )
            
            if obs_count and obs_count > 0:
                return {
                    "id_zone": zone["id_zone"],
                    "parcelle_id": zone["id_parcelle"],
                    "parcelle_nom": zone["parcelle_nom"],
                    "total_observations": zone["nombre_observations"],
                    "centre": {"lat": zone["centre_latitude"], "lon": zone["centre_longitude"]},
                    "zone_type": zone["zone_type"],
                    "maladies": [{"nom": "Non classifie", "count": obs_count, "pourcentage": 100.0}]
                }
            return {"error": f"Aucune observation trouvee dans la zone #{id_zone}"}
        
        # Nettoyer les maladies
        maladies_clean = []
        for m in maladies:
            nom = m["nom"]
            if nom and nom != "Inconnue":
                maladies_clean.append({
                    "nom": nom,
                    "count": m["count"],
                    "pourcentage": m["pourcentage"]
                })
        
        return {
            "id_zone": zone["id_zone"],
            "parcelle_id": zone["id_parcelle"],
            "parcelle_nom": zone["parcelle_nom"],
            "total_observations": zone["nombre_observations"],
            "centre": {"lat": zone["centre_latitude"], "lon": zone["centre_longitude"]},
            "zone_type": zone["zone_type"],
            "maladies": maladies_clean
        }
        
    except Exception as e:
        print(f"❌ Erreur dans get_zone_detail: {e}")
        import traceback
        traceback.print_exc()
        return {"error": str(e)}
    finally:
        await conn.close()

# ============================================================
# EXPORT DES ZONES EN CSV - AVEC RAYON_GROUPEMENT_M
# ============================================================
@router.get("/export/zones")
async def export_zones(
    user_id: int = Query(1),
    periode: str = Query("30j", description="7j, 30j, 90j, 365j"),
    parcelle_id: int | None = Query(None),
    zone_type: str | None = Query(None, description="DANS_PARCELLE, HORS_PARCELLE, MULTI_PARCELLES")
):
    """
    Exporte toutes les zones de l'utilisateur avec détails des maladies en CSV
    Utilise RAYON_GROUPEMENT_M pour la recherche des maladies
    """
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        jours = {"7j": 7, "30j": 30, "90j": 90, "365j": 365}.get(periode, 30)
        date_debut = datetime.now() - timedelta(days=jours)

        zones_query = """
            SELECT 
                z.id_zone,
                z.centre_latitude,
                z.centre_longitude,
                z.rayon,
                z.nombre_observations,
                z.zone_type,
                COALESCE(p.nom, 'Hors parcelle') as parcelle_nom,
                z.id_parcelle,
                z.id_utilisateur
            FROM zone_infectee z
            LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            WHERE z.id_utilisateur = $1
        """
        params = [user_id]
        param_index = 2

        if zone_type:
            zones_query += f" AND z.zone_type = ${param_index}"
            params.append(zone_type)
            param_index += 1

        if parcelle_id:
            zones_query += f" AND z.id_parcelle = ${param_index}"
            params.append(parcelle_id)
            param_index += 1

        zones_query += " ORDER BY z.id_zone"

        zones = await conn.fetch(zones_query, *params)

        if not zones:
            return {"error": "Aucune zone trouvée pour cet utilisateur"}

        result = []
        for zone in zones:
            # ✅ Utiliser RAYON_GROUPEMENT_M depuis settings
            # On prend le max entre le rayon de la zone et RAYON_GROUPEMENT_M
            rayon_recherche = max(zone['rayon'], settings.RAYON_GROUPEMENT_M)
            print(f"🔍 Zone #{zone['id_zone']}: rayon zone={zone['rayon']}m, recherche={rayon_recherche}m")

            maladies = await conn.fetch("""
                SELECT 
                    o.maladie_nom,
                    COUNT(*) as count,
                    ROUND(COUNT(*) * 100.0 / $1, 1) as pourcentage
                FROM observation o
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE d.id_utilisateur = $2
                    AND ST_DWithin(
                        ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                        ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography,
                        $5
                    )
                GROUP BY o.maladie_nom
                ORDER BY count DESC
            """, zone['nombre_observations'], user_id, 
                zone['centre_longitude'], zone['centre_latitude'], rayon_recherche)

            # Formater les maladies
            maladies_counts = {}
            for m in maladies:
                nom = m['maladie_nom']
                if nom:
                    nom_clean = nom.replace('Tomato_', '').replace('_', ' ')
                    if nom_clean == 'healthy':
                        nom_clean = 'Sain'
                    elif nom_clean == 'Early Blight':
                        nom_clean = 'Alternariose'
                    elif nom_clean == 'Late blight':
                        nom_clean = 'Mildiou'
                    elif nom_clean == 'leaf yellow curl virus':
                        nom_clean = 'Virus jaune'
                    elif nom_clean == 'mold':
                        nom_clean = 'Moisissure'
                    elif nom_clean == 'Septoria leaf spot':
                        nom_clean = 'Septoriose'
                    
                    maladies_counts[nom_clean] = {
                        'count': m['count'],
                        'pourcentage': m['pourcentage']
                    }

            maladies_parts = []
            for nom, data in maladies_counts.items():
                maladies_parts.append(f"{nom}: {data['count']} ({data['pourcentage']}%)")
            maladies_str = " | ".join(maladies_parts) if maladies_parts else "Aucune"

            nb_obs = zone['nombre_observations']
            if nb_obs >= 20:
                niveau = "Critique"
            elif nb_obs >= 10:
                niveau = "Actif"
            elif nb_obs >= 5:
                niveau = "Émergent"
            else:
                niveau = "Faible"

            result.append({
                "id_zone": zone['id_zone'],
                "latitude": zone['centre_latitude'],
                "longitude": zone['centre_longitude'],
                "rayon": zone['rayon'],
                "nombre_observations": zone['nombre_observations'],
                "zone_type": zone['zone_type'] or "HORS_PARCELLE",
                "parcelle": zone['parcelle_nom'] or "Hors parcelle",
                "niveau_alerte": niveau,
                "maladies": maladies_str,
                "total_maladies": len(maladies_counts)
            })

        # Générer le CSV
        output = StringIO()
        writer = csv.writer(output, delimiter=';', quoting=csv.QUOTE_MINIMAL)

        headers = [
            "ID Zone",
            "Latitude",
            "Longitude",
            "Rayon (m)",
            "Observations",
            "Type",
            "Parcelle",
            "Niveau d'alerte",
            "Maladies (détail)",
            "Nombre de maladies"
        ]
        writer.writerow(headers)

        for row in result:
            writer.writerow([
                row["id_zone"],
                f"{row['latitude']:.6f}",
                f"{row['longitude']:.6f}",
                f"{row['rayon']:.1f}",
                row["nombre_observations"],
                row["zone_type"],
                row["parcelle"],
                row["niveau_alerte"],
                row["maladies"],
                row["total_maladies"]
            ])

        csv_content = output.getvalue()
        output.close()

        csv_bytes = csv_content.encode('utf-8-sig')

        return Response(
            content=csv_bytes,
            media_type="text/csv",
            headers={
                "Content-Disposition": f"attachment; filename=zones_infectees_{datetime.now().strftime('%Y%m%d_%H%M')}.csv"
            }
        )

    except Exception as e:
        print(f"❌ Erreur export CSV: {e}")
        raise HTTPException(status_code=500, detail=f"Erreur lors de l'export: {str(e)}")
    finally:
        await conn.close()
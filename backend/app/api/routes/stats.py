from fastapi import APIRouter, HTTPException, Query
from datetime import datetime, timedelta
import asyncpg
import csv
from io import StringIO
from fastapi import Response
from app.core.config import settings

router = APIRouter()

# ✅ Maladies à EXCLURE du calcul des taux UNIQUEMENT
EXCLUDED_FOR_RATE = {"Tomato_Healthy", "Non identifiable", "Sain"}


def is_maladie_active(maladie_nom: str | None) -> bool:
    """Retourne True si la maladie est active (non saine)"""
    return bool(maladie_nom and maladie_nom not in EXCLUDED_FOR_RATE)


def normalize_maladie_name(maladie_nom: str | None) -> str:
    """Normalise le nom d'une maladie pour l'affichage"""
    if not maladie_nom:
        return "Inconnue"
    mapping = {
        "Tomato_Healthy": "Sain",
        "Tomato_Early_Blight": "Alternariose",
        "Tomato_leaf_late_blight": "Mildiou",
        "Tomato_leaf_yellow_curl_virus": "Virus jaune",
        "Tomato_mold_leaf": "Moisissure",
        "Tomato_Septoria_leaf_spot": "Septoriose",
        "Tomato_powdery_mildew": "Oïdium",
    }
    return mapping.get(maladie_nom, maladie_nom)


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
        date_debut = datetime.now() - timedelta(days=jours)
        
        # ============================================================
        # CONSTRUCTION DES FILTRES
        # ============================================================
        obs_filters = [
            "o.timestamp >= $1",
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
        
        # ============================================================
        # 1. Total observations
        # ============================================================
        total_observations = await conn.fetchval(f"""
            SELECT COUNT(DISTINCT o.id_observation)
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)

        total_diag = await conn.fetchval(f"""
            SELECT COUNT(DISTINCT d.id_diagnostic)
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)
        
        # ============================================================
        # 2. Total zones - DYNAMIQUE
        # ============================================================
        if maladie or parcelle_id:
            zone_params = [user_id, date_debut]
            zone_where = "z.id_utilisateur = $1 AND d.id_utilisateur = $1 AND o.timestamp >= $2"
            zone_idx = 3
            
            if maladie:
                zone_where += f" AND o.maladie_nom = ${zone_idx}"
                zone_params.append(maladie)
                zone_idx += 1
            if parcelle_id:
                zone_where += f" AND o.id_parcelle = ${zone_idx}"
                zone_params.append(parcelle_id)
                zone_idx += 1
            
            total_zones = await conn.fetchval(f"""
                SELECT COUNT(DISTINCT z.id_zone)
                FROM zone_infectee z
                LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
                LEFT JOIN observation o ON ST_DWithin(
                    ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint(z.centre_longitude, z.centre_latitude), 4326)::geography,
                    z.rayon
                )
                LEFT JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE {zone_where}
            """, *zone_params)
        else:
            total_zones = await conn.fetchval("""
                SELECT COUNT(DISTINCT z.id_zone)
                FROM zone_infectee z
                WHERE z.id_utilisateur = $1
            """, user_id)
        
        # ============================================================
        # 3. Total parcelles - DYNAMIQUE
        # ============================================================
        if parcelle_id:
            total_parcelles = 1
        elif maladie:
            total_parcelles = await conn.fetchval(f"""
                SELECT COUNT(DISTINCT p.id_parcelle)
                FROM parcelle p
                JOIN observation o ON o.id_parcelle = p.id_parcelle
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE p.id_utilisateur = $1
                    AND d.id_utilisateur = $1
                    AND o.timestamp >= $2
                    AND o.maladie_nom = $3
            """, user_id, date_debut, maladie)
        else:
            total_parcelles = await conn.fetchval("""
                SELECT COUNT(*) FROM parcelle WHERE id_utilisateur = $1
            """, user_id)
        
        # ============================================================
        # 4. Taux infection moyen
        # ============================================================
        taux_moyen = await conn.fetchval(f"""
            SELECT 
                CASE WHEN COUNT(DISTINCT o.id_observation) > 0 
                THEN SUM(CASE 
                    WHEN o.maladie_nom NOT IN ('Tomato_Healthy', 'Non identifiable', 'Sain') 
                    AND o.maladie_nom IS NOT NULL 
                    THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT o.id_observation)
                ELSE 0 END
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)
        
        # ============================================================
        # 5. Répartition par maladie
        # ============================================================
        repartition = await conn.fetch(f"""
            SELECT o.maladie_nom as maladie_nom, COUNT(*) as count
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
                AND o.maladie_nom IS NOT NULL
                AND o.maladie_nom NOT IN ('Non identifiable')
            GROUP BY o.maladie_nom
            ORDER BY count DESC
        """, *params)

        total_observed = sum((row['count'] or 0) for row in repartition)
        repartition_clean = []
        for row in repartition:
            nom = normalize_maladie_name(row['maladie_nom'])
            if nom:
                count = row['count'] or 0
                pourcentage = round(count * 100.0 / total_observed, 1) if total_observed else 0
                repartition_clean.append({
                    "nom": nom,
                    "count": count,
                    "pourcentage": pourcentage,
                })
        
        # ============================================================
        # 6. TOP ZONES - DYNAMIQUE
        # ============================================================
        
        # Construire les filtres pour les zones
        zone_filters = [
            "z.id_utilisateur = $1",
            "d.id_utilisateur = $1",
            "o.timestamp >= $2"
        ]
        zone_params = [user_id, date_debut]
        zone_idx = 3
        
        if maladie:
            zone_filters.append(f"o.maladie_nom = ${zone_idx}")
            zone_params.append(maladie)
            zone_idx += 1
        
        if parcelle_id:
            zone_filters.append(f"o.id_parcelle = ${zone_idx}")
            zone_params.append(parcelle_id)
            zone_idx += 1
        
        zone_where = " AND ".join(zone_filters)
        
        top_zones = await conn.fetch(f"""
            WITH zone_data AS (
                SELECT 
                    z.id_zone,
                    COALESCE(p.nom, 'Hors parcelle') as parcelle_nom,
                    COUNT(o.id_observation) as total_observations,
                    SUM(CASE 
                        WHEN o.maladie_nom NOT IN ('Tomato_Healthy', 'Non identifiable', 'Sain') 
                        AND o.maladie_nom IS NOT NULL 
                        THEN 1 ELSE 0 END) as observations_malades
                FROM zone_infectee z
                LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
                LEFT JOIN observation o ON ST_DWithin(
                    ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint(z.centre_longitude, z.centre_latitude), 4326)::geography,
                    z.rayon
                )
                LEFT JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE {zone_where}
                GROUP BY z.id_zone, p.nom
            )
            SELECT 
                id_zone,
                parcelle_nom,
                total_observations,
                observations_malades,
                ROUND(observations_malades * 100.0 / NULLIF(total_observations, 0), 1) as taux_infection
            FROM zone_data
            WHERE observations_malades > 0
            ORDER BY observations_malades DESC
            LIMIT 5
        """, *zone_params)
        
        top_zones_clean = [{
            "id_zone": z["id_zone"],
            "observations_malades": z["observations_malades"],
            "total_observations": z["total_observations"],
            "taux_infection": z["taux_infection"],
            "parcelle_nom": z["parcelle_nom"]
        } for z in top_zones]
        
        # ============================================================
        # 7. Top parcelles
        # ============================================================
        if maladie and not parcelle_id:
            top_parcelles = await conn.fetch(f"""
                SELECT 
                    p.id_parcelle,
                    p.nom,
                    COUNT(o.id_observation) as total_observations,
                    SUM(CASE 
                        WHEN o.maladie_nom NOT IN ('Tomato_Healthy', 'Non identifiable', 'Sain') 
                        AND o.maladie_nom IS NOT NULL 
                        THEN 1 ELSE 0 END) as observations_malades,
                    ROUND(
                        SUM(CASE 
                            WHEN o.maladie_nom NOT IN ('Tomato_Healthy', 'Non identifiable', 'Sain') 
                            AND o.maladie_nom IS NOT NULL 
                            THEN 1 ELSE 0 END) * 100.0 / COUNT(o.id_observation), 1
                    ) as taux_infection,
                    SUM(CASE WHEN o.maladie_nom = $2 THEN 1 ELSE 0 END) as selected_count
                FROM parcelle p
                JOIN observation o ON o.id_parcelle = p.id_parcelle
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE p.id_utilisateur = $1
                    AND d.id_utilisateur = $1
                    AND o.timestamp >= $3
                GROUP BY p.id_parcelle, p.nom
                HAVING SUM(CASE WHEN o.maladie_nom = $2 THEN 1 ELSE 0 END) > 0
                ORDER BY selected_count DESC
                LIMIT 5
            """, user_id, maladie, date_debut)
        else:
            query_params = [user_id, date_debut]
            parcelle_filter = ""
            if parcelle_id:
                parcelle_filter = "AND p.id_parcelle = $3"
                query_params.append(parcelle_id)

            top_parcelles = await conn.fetch(f"""
                SELECT 
                    p.id_parcelle,
                    p.nom,
                    COUNT(o.id_observation) as total_observations,
                    SUM(CASE 
                        WHEN o.maladie_nom NOT IN ('Tomato_Healthy', 'Non identifiable', 'Sain') 
                        AND o.maladie_nom IS NOT NULL 
                        THEN 1 ELSE 0 END) as observations_malades,
                    ROUND(
                        SUM(CASE 
                            WHEN o.maladie_nom NOT IN ('Tomato_Healthy', 'Non identifiable', 'Sain') 
                            AND o.maladie_nom IS NOT NULL 
                            THEN 1 ELSE 0 END) * 100.0 / COUNT(o.id_observation), 1
                    ) as taux_infection
                FROM parcelle p
                JOIN observation o ON o.id_parcelle = p.id_parcelle
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE p.id_utilisateur = $1
                    AND d.id_utilisateur = $1
                    AND o.timestamp >= $2
                {parcelle_filter}
                GROUP BY p.id_parcelle, p.nom
                ORDER BY taux_infection DESC
                LIMIT 5
            """, *query_params)
        
        return {
            "total_observations": total_observations or 0,
            "total_diagnostics": total_diag or 0,
            "total_zones": total_zones or 0,
            "total_parcelles": total_parcelles or 0,
            "taux_infection_moyen": round(taux_moyen or 0, 1),
            "repartition_maladies": repartition_clean,
            "top_zones": top_zones_clean,
            "top_parcelles": [dict(p) for p in top_parcelles]
        }
    except Exception as e:
        print(f"❌ Erreur dans /stats: {e}")
        import traceback
        traceback.print_exc()
        raise
    finally:
        await conn.close()


@router.get("/stats/zone/{id_zone}")
async def get_zone_detail(
    id_zone: int,
    user_id: int = Query(1),
    periode: str = Query("30j", description="7j, 30j, 90j, 365j"),
    parcelle_id: int | None = Query(None),
    maladie: str | None = Query(None),
):
    """
    Récupère les détails d'une zone avec répartition des maladies.
    ✅ total_observations = TOUTES les observations (saines + malades)
    ✅ observations_malades = UNIQUEMENT les malades
    ✅ taux_infection = malades / total * 100
    """
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
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
        
        jours = {"7j": 7, "30j": 30, "90j": 90, "365j": 365}.get(periode, 30)
        date_debut = datetime.now() - timedelta(days=jours)
        
        rayon_recherche = max(zone["rayon"], 3.0)
        
        obs_filters = [
            "d.id_utilisateur = $4",
            "o.timestamp >= $5"
        ]
        params = [zone["centre_longitude"], zone["centre_latitude"], rayon_recherche, user_id, date_debut]
        param_index = 6
        
        if parcelle_id:
            obs_filters.append(f"o.id_parcelle = ${param_index}")
            params.append(parcelle_id)
            param_index += 1
        if maladie:
            obs_filters.append(f"o.maladie_nom = ${param_index}")
            params.append(maladie)
            param_index += 1
        
        where_clause = " AND ".join(obs_filters)
        
        # ✅ total_observations = TOUTES les observations
        total_observations = await conn.fetchval(f"""
            SELECT COUNT(*)
            FROM observation o
            JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
            WHERE ST_DWithin(
                ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                $3
            )
            AND {where_clause}
        """, *params)
        
        if total_observations == 0:
            return {
                "id_zone": zone["id_zone"],
                "parcelle_id": zone["id_parcelle"],
                "parcelle_nom": zone["parcelle_nom"],
                "total_observations": 0,
                "observations_malades": 0,
                "taux_infection": 0,
                "centre": {"lat": zone["centre_latitude"], "lon": zone["centre_longitude"]},
                "zone_type": zone["zone_type"],
                "maladies": []
            }
        
        # ✅ Répartition incluant les saines
        maladies = await conn.fetch(f"""
            SELECT 
                CASE 
                    WHEN o.maladie_nom = 'Tomato_Healthy' THEN 'Sain'
                    ELSE o.maladie_nom
                END as maladie_nom,
                COUNT(*) as count,
                ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) as pourcentage
            FROM observation o
            JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
            WHERE ST_DWithin(
                ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                $3
            )
            AND {where_clause}
            AND o.maladie_nom IS NOT NULL
            AND o.maladie_nom NOT IN ('Non identifiable')
            GROUP BY o.maladie_nom
            ORDER BY count DESC
        """, *params)
        
        # ✅ Compter les malades (exclut "Sain")
        observations_malades = sum(m["count"] for m in maladies if m["maladie_nom"] != "Sain")
        
        # ✅ Taux d'infection = malades / total * 100
        taux_infection = round(observations_malades * 100.0 / total_observations, 1) if total_observations > 0 else 0
        
        maladies_clean = []
        for m in maladies:
            nom = m['maladie_nom']
            if nom:
                nom_clean = normalize_maladie_name(nom)
                maladies_clean.append({
                    "nom": nom_clean,
                    "count": m["count"],
                    "pourcentage": m["pourcentage"]
                })

        return {
            "id_zone": zone["id_zone"],
            "parcelle_id": zone["id_parcelle"],
            "parcelle_nom": zone["parcelle_nom"],
            "total_observations": total_observations,
            "observations_malades": observations_malades,
            "taux_infection": taux_infection,
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
# EXPORT DES ZONES EN CSV
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
    ✅ total_observations = TOUTES les observations
    ✅ observations_malades = UNIQUEMENT les malades
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
            rayon_recherche = max(zone['rayon'], settings.RAYON_GROUPEMENT_M)

            # ✅ Inclure toutes les observations (saines + malades)
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
                    AND o.maladie_nom IS NOT NULL
                    AND o.maladie_nom NOT IN ('Non identifiable')
                GROUP BY o.maladie_nom
                ORDER BY count DESC
            """, zone['nombre_observations'], user_id, 
                zone['centre_longitude'], zone['centre_latitude'], rayon_recherche)

            # Compter les malades
            total_obs = sum(m["count"] for m in maladies)
            obs_malades = sum(m["count"] for m in maladies if m["maladie_nom"] != "Tomato_Healthy")
            taux = round(obs_malades * 100.0 / total_obs, 1) if total_obs > 0 else 0

            maladies_counts = {}
            for m in maladies:
                nom = m['maladie_nom']
                if nom:
                    nom_clean = normalize_maladie_name(nom)
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
                "total_observations": total_obs,
                "observations_malades": obs_malades,
                "taux_infection": taux,
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
            "Total Observations",
            "Observations Malades",
            "Taux d'infection (%)",
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
                row["total_observations"],
                row["observations_malades"],
                row["taux_infection"],
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
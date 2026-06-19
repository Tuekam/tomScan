# backend/app/api/routes/stats.py
from fastapi import APIRouter, Query
import asyncpg
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
        
        # Filtres pour les observations
        obs_filters = [
            "o.timestamp >= NOW() - INTERVAL '1 day' * $1",
            "d.id_utilisateur = $2"  # ← FILTRER PAR UTILISATEUR
        ]
        params = [jours, user_id]
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
        
        # 1. Total diagnostics (filtré par utilisateur)
        total_diag = await conn.fetchval(f"""
            SELECT COUNT(DISTINCT d.id_diagnostic)
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)
        
        # 2. Total zones (filtré par utilisateur via les parcelles)
        total_zones = await conn.fetchval("""
            SELECT COUNT(DISTINCT z.id_zone)
            FROM zone_infectee z
            JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            WHERE p.id_utilisateur = $1
        """, user_id)
        
        # 3. Total parcelles (filtré par utilisateur)
        total_parcelles = await conn.fetchval("""
            SELECT COUNT(*) FROM parcelle WHERE id_utilisateur = $1
        """, user_id)
        
        # 4. Taux infection moyen (filtré par utilisateur)
        taux_moyen = await conn.fetchval(f"""
            SELECT 
                CASE WHEN COUNT(*) > 0 
                THEN SUM(CASE WHEN o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable') THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
                ELSE 0 END
            FROM diagnostic d
            JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            WHERE {where_clause}
        """, *params)
        
        # 5. Répartition par maladie (filtré par utilisateur)
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
        
        # 6. Top zones (filtré par utilisateur)
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
                    WHERE d.id_utilisateur = $1 AND o.maladie_nom = $2
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
                JOIN parcelle p ON z.id_parcelle = p.id_parcelle
                WHERE p.id_utilisateur = $1
                ORDER BY z.nombre_observations DESC
                LIMIT 5
            """, user_id)
            top_zones_clean = [{
                "id_zone": z["id_zone"],
                "nombre_observations": z["nombre_observations"],
                "parcelle_nom": z["parcelle_nom"]
            } for z in top_zones]
        
        # 7. Top parcelles (filtré par utilisateur)
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
        
        # Nettoyage des noms
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
        zone = await conn.fetchrow("""
            SELECT 
                z.id_zone,
                z.centre_latitude,
                z.centre_longitude,
                z.nombre_observations,
                z.zone_type,
                z.id_parcelle,
                COALESCE(p.nom, 'Hors parcelle') as parcelle_nom
            FROM zone_infectee z
            LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            WHERE z.id_zone = $1 AND p.id_utilisateur = $2
        """, id_zone, user_id)
        
        if not zone:
            return {"error": "Zone non trouvée"}
        
        maladies = await conn.fetch("""
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
                1.0
            )
            AND d.id_utilisateur = $4
            GROUP BY o.maladie_nom
            ORDER BY count DESC
        """, zone["nombre_observations"], zone["centre_longitude"], zone["centre_latitude"], user_id)
        
        return {
            "id_zone": zone["id_zone"],
            "parcelle_id": zone["id_parcelle"],
            "parcelle_nom": zone["parcelle_nom"],
            "total_observations": zone["nombre_observations"],
            "centre": {"lat": zone["centre_latitude"], "lon": zone["centre_longitude"]},
            "zone_type": zone["zone_type"],
            "maladies": [{"nom": m["nom"], "count": m["count"], "pourcentage": m["pourcentage"]} for m in maladies if m["nom"] and m["nom"] != "Inconnue"]
        }
    except Exception as e:
        print(f"Erreur dans get_zone_detail: {e}")
        return {"error": str(e)}
    finally:
        await conn.close()
# backend/app/api/routes/zones.py
from fastapi import APIRouter, Query
import asyncpg
from app.core.config import settings

router = APIRouter()

@router.get("/zones")
async def get_zones(user_id: int = Query(1)):
    """Récupère UNIQUEMENT les zones infectées de l'utilisateur"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        rows = await conn.fetch("""
            SELECT 
                z.id_zone,
                z.centre_latitude,
                z.centre_longitude,
                z.rayon,
                z.nombre_observations,
                z.zone_type,
                z.id_parcelle,
                z.id_utilisateur,
                p.nom as parcelle_nom
            FROM zone_infectee z
            LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            WHERE z.id_utilisateur = $1
            ORDER BY z.id_zone
        """, user_id)
        
        features = []
        for row in rows:
            zone_type = row['zone_type'] or "HORS_PARCELLE"
            nombre_obs = row['nombre_observations']
            
            if row['id_parcelle'] is None:
                parcelle_nom = "Hors parcelle"
            else:
                parcelle_nom = row['parcelle_nom'] or "Parcelle"
            
            if zone_type == "HORS_PARCELLE":
                couleur = "orange"
                niveau = "Hors parcelle"
            elif zone_type == "MULTI_PARCELLES":
                couleur = "red"
                niveau = "Multi-parcelles"
            else:
                if nombre_obs >= 20:
                    couleur = "red"
                    niveau = "Critique"
                elif nombre_obs >= 10:
                    couleur = "orange"
                    niveau = "Actif"
                else:
                    couleur = "yellow"
                    niveau = "Émergent"
            
            popup_text = f"Zone #{row['id_zone']} - {niveau}"
            if parcelle_nom:
                popup_text += f" - {parcelle_nom}"
            popup_text += f" - {nombre_obs} obs"
            
            features.append({
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [row["centre_longitude"], row["centre_latitude"]]
                },
                "properties": {
                    "id": row["id_zone"],
                    "rayon": row["rayon"],
                    "nombre_observations": nombre_obs,
                    "couleur": couleur,
                    "zone_type": zone_type,
                    "id_parcelle": row["id_parcelle"],
                    "id_utilisateur": row["id_utilisateur"],
                    "parcelle_nom": parcelle_nom,
                    "popup_text": popup_text
                }
            })
        
        return {
            "type": "FeatureCollection",
            "features": features
        }
    finally:
        await conn.close()
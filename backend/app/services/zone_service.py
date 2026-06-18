# backend/app/services/zone_service.py
import math
import asyncpg
from app.repositories.zone_repository import ZoneRepository
from app.repositories.observation_repository import ObservationRepository
from app.core.config import settings

class ZoneService:
    def __init__(self):
        self.zone_repo = ZoneRepository()
        self.obs_repo = ObservationRepository()

    def distance_en_mètres(self, lat1, lon1, lat2, lon2):
        """Formule de Haversine"""
        R = 6371000
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlambda = math.radians(lon2 - lon1)

        a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
        return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    async def trouver_parcelle_contenant_point(self, lat: float, lon: float) -> int | None:
        """Trouve la parcelle qui contient ce point géographique"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT id_parcelle 
                FROM parcelle 
                WHERE ST_Contains(polygone, ST_SetSRID(ST_MakePoint($1, $2), 4326))
                LIMIT 1
            """, lon, lat)  # longitude, latitude
            return row['id_parcelle'] if row else None
        finally:
            await conn.close()

    async def trouver_parcelles_autour_point(self, lat: float, lon: float, rayon_m: float = 1.0) -> list:
        """Trouve toutes les parcelles dans un rayon autour du point"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch("""
                SELECT DISTINCT id_parcelle, nom
                FROM parcelle
                WHERE ST_DWithin(
                    polygone,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326),
                    $3
                )
            """, lon, lat, rayon_m)
            return [dict(row) for row in rows]
        finally:
            await conn.close()

    async def regrouper_observations_avec_parcelles(self, nouvelle_obs: dict):
        """Regroupe les observations et détermine les parcelles concernées"""
        
        # 1. Récupérer les observations existantes proches
        observations_proches = await self.obs_repo.get_observations_proches(
            nouvelle_obs["latitude"], nouvelle_obs["longitude"], rayon=3
        )
        
        toutes_obs = observations_proches + [nouvelle_obs]
        
        # 2. Déterminer les parcelles concernées par ces observations
        parcelles_concernees = set()
        
        for obs in toutes_obs:
            parcelle_id = await self.trouver_parcelle_contenant_point(
                obs["latitude"], obs["longitude"]
            )
            if parcelle_id:
                parcelles_concernees.add(parcelle_id)
        
        # 3. Si on a assez d'observations (≥10), créer ou mettre à jour une zone
        if len(toutes_obs) >= 10:
            # Calculer le centre de gravité
            centre_lat = sum(o["latitude"] for o in toutes_obs) / len(toutes_obs)
            centre_lon = sum(o["longitude"] for o in toutes_obs) / len(toutes_obs)
            
            # Déterminer le type de zone
            if len(parcelles_concernees) == 0:
                zone_type = "HORS_PARCELLE"
            elif len(parcelles_concernees) == 1:
                zone_type = "DANS_PARCELLE"
            else:
                zone_type = "MULTI_PARCELLES"
            
            # Récupérer l'ID de parcelle (si une seule)
            id_parcelle = list(parcelles_concernees)[0] if len(parcelles_concernees) == 1 else None
            
            # Sauvegarder la zone
            await self.zone_repo.save_or_update_zone(
                centre_lat=centre_lat,
                centre_lon=centre_lon,
                rayon=1.0,
                nombre_obs=len(toutes_obs),
                id_parcelle=id_parcelle,
                zone_type=zone_type,
                parcelles_multi=list(parcelles_concernees) if len(parcelles_concernees) > 1 else []
            )
            
            return {
                "zone_creee": True,
                "zone_type": zone_type,
                "id_parcelle": id_parcelle,
                "parcelles_concernees": list(parcelles_concernees)
            }
        
        return {"zone_creee": False}
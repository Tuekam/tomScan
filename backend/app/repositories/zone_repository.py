# backend/app/repositories/zone_repository.py
import asyncpg
import math
from app.core.config import settings

class ZoneRepository:
    
    def _distance_en_metres(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Distance Haversine entre deux points GPS"""
        R = 6371000
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlambda = math.radians(lon2 - lon1)
        a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
        return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    async def zone_existe_proche(self, lat: float, lon: float, rayon_m: float = None) -> int | None:
        """Vérifie si une zone existe à proximité (rayon en mètres)"""
        if rayon_m is None:
            rayon_m = settings.RAYON_GROUPEMENT_M
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT id_zone 
                FROM zone_infectee
                WHERE ST_DWithin(
                    ST_SetSRID(ST_MakePoint(centre_longitude, centre_latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                    $3
                )
                LIMIT 1
            """, lon, lat, rayon_m)
            return row['id_zone'] if row else None
        finally:
            await conn.close()
    
    # ============================================================
    # ✅ CORRIGÉ : trouver_zone_proche_observation
    # ============================================================
    async def trouver_zone_proche_observation(self, lat: float, lon: float, rayon_m: float = None) -> int | None:
        """
        Trouve une zone existante qui peut accueillir une nouvelle observation.
        Utilise le rayon de regroupement (et non le rayon de la zone).
        """
        if rayon_m is None:
            rayon_m = settings.RAYON_GROUPEMENT_M
        
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT z.id_zone
                FROM zone_infectee z
                WHERE ST_DWithin(
                    ST_SetSRID(ST_MakePoint(z.centre_longitude, z.centre_latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                    $3
                )
                LIMIT 1
            """, lon, lat, rayon_m)
            return row['id_zone'] if row else None
        finally:
            await conn.close()
    
    # ============================================================
    # ✅ ajouter_observation_a_zone
    # ============================================================
    async def ajouter_observation_a_zone(self, id_zone: int, id_observation: int, 
                                          lat: float, lon: float, maladie: str) -> None:
        """
        Ajoute une observation à une zone existante.
        """
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            await conn.execute("""
                UPDATE observation 
                SET id_zone = $1 
                WHERE id_observation = $2
            """, id_zone, id_observation)
            print(f"   ✅ Observation #{id_observation} ajoutée à la zone #{id_zone}")
        finally:
            await conn.close()
    
    # ============================================================
    # ✅ recalculer_zone
    # ============================================================
    async def recalculer_zone(self, id_zone: int) -> None:
        """
        Recalcule le centre, le nombre d'observations et le rayon d'une zone.
        À appeler après chaque ajout d'observation.
        """
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            observations = await conn.fetch("""
                SELECT latitude, longitude
                FROM observation
                WHERE id_zone = $1
            """, id_zone)
            
            if not observations:
                return
            
            nb_obs = len(observations)
            
            centre_lat = sum(o["latitude"] for o in observations) / nb_obs
            centre_lon = sum(o["longitude"] for o in observations) / nb_obs
            
            rayon_reel = 0.0
            for obs in observations:
                dist = self._distance_en_metres(
                    centre_lat, centre_lon,
                    obs["latitude"], obs["longitude"]
                )
                if dist > rayon_reel:
                    rayon_reel = dist
            rayon_reel = round(rayon_reel, 2)
            
            await conn.execute("""
                UPDATE zone_infectee 
                SET nombre_observations = $1,
                    centre_latitude = $2,
                    centre_longitude = $3,
                    rayon = $4
                WHERE id_zone = $5
            """, nb_obs, centre_lat, centre_lon, rayon_reel, id_zone)
            
            print(f"   ✅ Zone #{id_zone} recalculée: {nb_obs} observations, rayon {rayon_reel}m")
        finally:
            await conn.close()
    
    # ============================================================
    # MÉTHODES EXISTANTES
    # ============================================================
    
    async def creer_zone(self, centre_lat: float, centre_lon: float, 
                         nombre_obs: int, observations: list,
                         id_parcelle: int | None = None,
                         zone_type: str = "HORS_PARCELLE",
                         id_utilisateur: int = 1) -> int:
        """Crée une nouvelle zone infectée avec rayon dynamique"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rayon_reel = 0.0
            if observations and len(observations) > 0:
                for obs in observations:
                    dist = self._distance_en_metres(
                        centre_lat, centre_lon,
                        obs["latitude"], obs["longitude"]
                    )
                    if dist > rayon_reel:
                        rayon_reel = dist
                rayon_reel = round(rayon_reel, 2)
                print(f"📐 Rayon dynamique calculé: {rayon_reel}m")
            else:
                rayon_reel = settings.RAYON_GROUPEMENT_M
                print(f"📐 Rayon par défaut: {rayon_reel}m")
            
            row = await conn.fetchrow("""
                INSERT INTO zone_infectee 
                    (centre_latitude, centre_longitude, rayon, nombre_observations, id_parcelle, zone_type, id_utilisateur)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id_zone
            """, centre_lat, centre_lon, rayon_reel, nombre_obs, id_parcelle, zone_type, id_utilisateur)
            
            if observations:
                obs_ids = [o.get("id_observation") for o in observations if o.get("id_observation")]
                if obs_ids:
                    await conn.execute("""
                        UPDATE observation 
                        SET id_zone = $1 
                        WHERE id_observation = ANY($2::int[])
                    """, row['id_zone'], obs_ids)
            
            print(f"   ✅ Nouvelle zone #{row['id_zone']} créée ({zone_type}) avec rayon {rayon_reel}m")
            return row['id_zone']
        finally:
            await conn.close()
    
    async def mettre_a_jour_zone(self, id_zone: int, nouvelles_obs: int,
                                  nouveau_centre_lat: float, nouveau_centre_lon: float,
                                  zone_type: str = None) -> None:
        """Met à jour une zone existante (sans recalcul du rayon)"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            ancienne = await conn.fetchrow("""
                SELECT nombre_observations, centre_latitude, centre_longitude
                FROM zone_infectee
                WHERE id_zone = $1
            """, id_zone)
            
            if ancienne:
                total_obs = ancienne['nombre_observations'] + nouvelles_obs
                new_lat = (ancienne['centre_latitude'] * ancienne['nombre_observations'] + 
                           nouveau_centre_lat * nouvelles_obs) / total_obs
                new_lon = (ancienne['centre_longitude'] * ancienne['nombre_observations'] + 
                           nouveau_centre_lon * nouvelles_obs) / total_obs
                
                if zone_type:
                    await conn.execute("""
                        UPDATE zone_infectee 
                        SET nombre_observations = $1,
                            centre_latitude = $2,
                            centre_longitude = $3,
                            zone_type = $4
                        WHERE id_zone = $5
                    """, total_obs, new_lat, new_lon, zone_type, id_zone)
                else:
                    await conn.execute("""
                        UPDATE zone_infectee 
                        SET nombre_observations = $1,
                            centre_latitude = $2,
                            centre_longitude = $3
                        WHERE id_zone = $4
                    """, total_obs, new_lat, new_lon, id_zone)
                print(f"   ✅ Zone #{id_zone} mise à jour ({total_obs} observations)")
        finally:
            await conn.close()
    
    async def get_toutes_les_zones(self) -> list[dict]:
        """Récupère toutes les zones (admin)"""
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
                ORDER BY z.id_zone
            """)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    async def get_zones_by_user(self, user_id: int) -> list[dict]:
        """Récupère uniquement les zones de l'utilisateur"""
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
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    async def get_zone_by_id(self, id_zone: int) -> dict | None:
        """Récupère une zone par son ID"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT id_zone, nombre_observations, centre_latitude, centre_longitude, rayon, zone_type, id_utilisateur
                FROM zone_infectee
                WHERE id_zone = $1
            """, id_zone)
            return dict(row) if row else None
        finally:
            await conn.close()
    
    async def mettre_a_jour_zone_simple(self, id_zone: int, nb_obs: int, 
                                         centre_lat: float, centre_lon: float, 
                                         zone_type: str = None,
                                         observations: list = None) -> None:
        """Met à jour une zone avec recalcul du centre et du rayon"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            if observations is None:
                observations = await conn.fetch("""
                    SELECT latitude, longitude
                    FROM observation
                    WHERE id_zone = $1
                """, id_zone)
            
            rayon_reel = settings.RAYON_GROUPEMENT_M
            if observations and len(observations) > 0:
                rayon_reel = 0.0
                for obs in observations:
                    dist = self._distance_en_metres(
                        centre_lat, centre_lon,
                        obs["latitude"], obs["longitude"]
                    )
                    if dist > rayon_reel:
                        rayon_reel = dist
                rayon_reel = round(rayon_reel, 2)
                print(f"📐 Rayon recalculé: {rayon_reel}m")
            
            if zone_type:
                await conn.execute("""
                    UPDATE zone_infectee 
                    SET nombre_observations = $1,
                        centre_latitude = $2,
                        centre_longitude = $3,
                        rayon = $4,
                        zone_type = $5
                    WHERE id_zone = $6
                """, nb_obs, centre_lat, centre_lon, rayon_reel, zone_type, id_zone)
            else:
                await conn.execute("""
                    UPDATE zone_infectee 
                    SET nombre_observations = $1,
                        centre_latitude = $2,
                        centre_longitude = $3,
                        rayon = $4
                    WHERE id_zone = $5
                """, nb_obs, centre_lat, centre_lon, rayon_reel, id_zone)
            
            print(f"   ✅ Zone #{id_zone} mise à jour: {nb_obs} observations, rayon {rayon_reel}m")
        finally:
            await conn.close()
    
    async def recalculer_zone_apres_suppression(self, id_zone: int) -> None:
        """Recalcule une zone après suppression d'observations"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            observations = await conn.fetch("""
                SELECT latitude, longitude
                FROM observation
                WHERE id_zone = $1
            """, id_zone)
            
            nb_obs = len(observations)
            
            if nb_obs < settings.SEUIL_CREATION_ZONE:
                await conn.execute("DELETE FROM zone_infectee WHERE id_zone = $1", id_zone)
                print(f"🗑️ Zone #{id_zone} supprimée (plus que {nb_obs} observations)")
                return
            
            centre_lat = sum(o["latitude"] for o in observations) / nb_obs
            centre_lon = sum(o["longitude"] for o in observations) / nb_obs
            
            rayon_reel = 0.0
            for obs in observations:
                dist = self._distance_en_metres(
                    centre_lat, centre_lon,
                    obs["latitude"], obs["longitude"]
                )
                if dist > rayon_reel:
                    rayon_reel = dist
            rayon_reel = round(rayon_reel, 2)
            
            await conn.execute("""
                UPDATE zone_infectee 
                SET nombre_observations = $1,
                    centre_latitude = $2,
                    centre_longitude = $3,
                    rayon = $4
                WHERE id_zone = $5
            """, nb_obs, centre_lat, centre_lon, rayon_reel, id_zone)
            
            print(f"🔄 Zone #{id_zone} mise à jour: {nb_obs} observations, rayon {rayon_reel}m")
        finally:
            await conn.close()

    # ============================================================
    # ✅ SUPPRIMER UNE ZONE
    # ============================================================
    async def supprimer_zone(self, id_zone: int, user_id: int) -> bool:
        """Supprime une zone et toutes les notifications liées"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow(
                "SELECT id_zone FROM zone_infectee WHERE id_zone = $1 AND id_utilisateur = $2",
                id_zone, user_id
            )
            if not row:
                return False
            
            await conn.execute("""
                UPDATE observation 
                SET id_zone = NULL 
                WHERE id_zone = $1
            """, id_zone)
            
            await conn.execute("DELETE FROM notification WHERE id_zone = $1", id_zone)
            print(f"🗑️ Notifications liées à la zone #{id_zone} supprimées")
            
            await conn.execute("DELETE FROM zone_infectee WHERE id_zone = $1", id_zone)
            print(f"🗑️ Zone #{id_zone} supprimée (utilisateur: {user_id})")
            return True
        finally:
            await conn.close()
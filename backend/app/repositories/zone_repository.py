# backend/app/repositories/zone_repository.py
import asyncpg
from app.core.config import settings

class ZoneRepository:
    
    async def zone_existe_proche(self, lat: float, lon: float, rayon_m: float = 1.0) -> int | None:
        """Vérifie si une zone existe à proximité (rayon en mètres)"""
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
    
    async def creer_zone(self, centre_lat: float, centre_lon: float, 
                         nombre_obs: int, id_parcelle: int | None = None,
                         zone_type: str = "HORS_PARCELLE") -> int:
        """Crée une nouvelle zone infectée"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                INSERT INTO zone_infectee 
                    (centre_latitude, centre_longitude, rayon, nombre_observations, id_parcelle, zone_type)
                VALUES ($1, $2, 1.0, $3, $4, $5)
                RETURNING id_zone
            """, centre_lat, centre_lon, nombre_obs, id_parcelle, zone_type)
            print(f"   ✅ Nouvelle zone #{row['id_zone']} créée ({zone_type})")
            return row['id_zone']
        finally:
            await conn.close()
    
    async def mettre_a_jour_zone(self, id_zone: int, nouvelles_obs: int,
                                  nouveau_centre_lat: float, nouveau_centre_lon: float,
                                  zone_type: str = None) -> None:
        """Met à jour une zone existante"""
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
        """Récupère toutes les zones"""
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
                    p.nom as parcelle_nom
                FROM zone_infectee z
                LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
                ORDER BY z.id_zone
            """)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    # ========== NOUVELLES MÉTHODES POUR PREDICT.PY ==========
    
    async def get_zone_by_id(self, id_zone: int) -> dict | None:
        """Récupère une zone par son ID"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT id_zone, nombre_observations, centre_latitude, centre_longitude, zone_type
                FROM zone_infectee
                WHERE id_zone = $1
            """, id_zone)
            return dict(row) if row else None
        finally:
            await conn.close()
    
    async def mettre_a_jour_zone_simple(self, id_zone: int, nb_obs: int, 
                                         centre_lat: float, centre_lon: float, 
                                         zone_type: str = None) -> None:
        """Met à jour une zone simplement (sans recalcul complexe)"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            if zone_type:
                await conn.execute("""
                    UPDATE zone_infectee 
                    SET nombre_observations = $1,
                        centre_latitude = $2,
                        centre_longitude = $3,
                        zone_type = $4
                    WHERE id_zone = $5
                """, nb_obs, centre_lat, centre_lon, zone_type, id_zone)
            else:
                await conn.execute("""
                    UPDATE zone_infectee 
                    SET nombre_observations = $1,
                        centre_latitude = $2,
                        centre_longitude = $3
                    WHERE id_zone = $4
                """, nb_obs, centre_lat, centre_lon, id_zone)
            print(f"   ✅ Zone #{id_zone} mise à jour: {nb_obs} observations")
        finally:
            await conn.close()
# backend/app/repositories/observation_repository.py
import asyncpg
from app.core.config import settings

class ObservationRepository:
    
    async def save_observation(self, id_diagnostic: int, id_maladie: int | None,
                                timestamp, latitude: float, longitude: float,
                                precision_gps: float, image_path: str,
                                confiance: float, maladie_nom: str,
                                id_parcelle: int | None = None) -> int:
        """Sauvegarde une observation"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                INSERT INTO observation 
                    (id_diagnostic, id_maladie, timestamp, latitude, longitude, 
                     precision_gps, image_path, confiance, maladie_nom, id_parcelle)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                RETURNING id_observation
            """, id_diagnostic, id_maladie, timestamp, latitude, longitude,
               precision_gps, image_path, confiance, maladie_nom, id_parcelle)
            return row['id_observation']
        finally:
            await conn.close()
    
    async def update_parcelle(self, id_observation: int, id_parcelle: int) -> None:
        """Met à jour la parcelle d'une observation"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            await conn.execute("""
                UPDATE observation 
                SET id_parcelle = $1 
                WHERE id_observation = $2
            """, id_parcelle, id_observation)
            print(f"   ✅ Observation #{id_observation} -> Parcelle #{id_parcelle}")
        except Exception as e:
            print(f"   ❌ Erreur update_parcelle: {e}")
        finally:
            await conn.close()
    
    async def get_all_observations(self) -> list[dict]:
        """Récupère toutes les observations"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch("""
                SELECT id_observation, latitude, longitude, id_parcelle
                FROM observation
                ORDER BY id_observation
            """)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    async def get_observations_proches(self, lat: float, lon: float, 
                                        rayon_m: float = 1.0, 
                                        exclude_id: int | None = None) -> list[dict]:
        """Récupère les observations dans un rayon donné (en mètres)"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            query = """
                SELECT id_observation, latitude, longitude, id_parcelle
                FROM observation
                WHERE ST_DWithin(
                    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                    $3
                )
            """
            params = [lon, lat, rayon_m]
            
            if exclude_id:
                query += " AND id_observation != $4"
                params.append(exclude_id)
            
            rows = await conn.fetch(query, *params)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    async def get_observations_by_parcelle(self, id_parcelle: int) -> list[dict]:
        """Récupère toutes les observations d'une parcelle"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch("""
                SELECT id_observation, latitude, longitude, maladie_nom, confiance, timestamp
                FROM observation
                WHERE id_parcelle = $1
                ORDER BY timestamp DESC
            """, id_parcelle)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    # ========== NOUVELLES MÉTHODES ==========
    
    async def delete_observation(self, id_observation: int) -> bool:
        """Supprime une observation"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            result = await conn.execute("DELETE FROM observation WHERE id_observation = $1", id_observation)
            # asyncpg retourne "DELETE <num>" 
            affected = int(result.split()[1]) if ' ' in result else 0
            return affected > 0
        finally:
            await conn.close()
    
    async def trouver_zone_associee(self, id_observation: int) -> int | None:
        """Trouve la zone infectée associée à une observation"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT z.id_zone
                FROM zone_infectee z
                CROSS JOIN observation o
                WHERE o.id_observation = $1
                AND ST_DWithin(
                    ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint(z.centre_longitude, z.centre_latitude), 4326)::geography,
                    z.rayon
                )
                LIMIT 1
            """, id_observation)
            return row["id_zone"] if row else None
        finally:
            await conn.close()
import asyncpg
from app.core.config import settings

class ZoneRepository:
    
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
    
    async def creer_zone(self, centre_lat: float, centre_lon: float, 
                         nombre_obs: int, id_parcelle: int | None = None,
                         zone_type: str = "HORS_PARCELLE",
                         id_utilisateur: int = 1) -> int:
        """Crée une nouvelle zone infectée avec l'utilisateur associé"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            # ✅ Utiliser le rayon depuis settings
            rayon = settings.RAYON_GROUPEMENT_M
            row = await conn.fetchrow("""
                INSERT INTO zone_infectee 
                    (centre_latitude, centre_longitude, rayon, nombre_observations, id_parcelle, zone_type, id_utilisateur)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id_zone
            """, centre_lat, centre_lon, rayon, nombre_obs, id_parcelle, zone_type, id_utilisateur)
            print(f"   ✅ Nouvelle zone #{row['id_zone']} créée ({zone_type}) avec rayon {rayon}m pour l'utilisateur {id_utilisateur}")
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
                
                # ✅ Garder le rayon existant ou utiliser le rayon par défaut
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
    
    async def recalculer_zone_apres_suppression(self, id_zone: int) -> None:
        """Recalcule une zone après suppression d'observations"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            zone = await conn.fetchrow("""
                SELECT centre_latitude, centre_longitude, rayon 
                FROM zone_infectee 
                WHERE id_zone = $1
            """, id_zone)
            
            if not zone:
                return
            
            observations = await conn.fetch("""
                SELECT id_observation, latitude, longitude
                FROM observation
                WHERE ST_DWithin(
                    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                    $3
                )
            """, zone["centre_longitude"], zone["centre_latitude"], zone["rayon"])
            
            nb_obs = len(observations)
            
            if nb_obs < 10:
                await conn.execute("DELETE FROM zone_infectee WHERE id_zone = $1", id_zone)
                print(f"🗑️ Zone #{id_zone} supprimée (plus que {nb_obs} observations)")
                return
            
            centre_lat = sum(o["latitude"] for o in observations) / nb_obs
            centre_lon = sum(o["longitude"] for o in observations) / nb_obs
            
            await conn.execute("""
                UPDATE zone_infectee 
                SET nombre_observations = $1,
                    centre_latitude = $2,
                    centre_longitude = $3
                WHERE id_zone = $4
            """, nb_obs, centre_lat, centre_lon, id_zone)
            
            print(f"🔄 Zone #{id_zone} mise à jour: {nb_obs} observations")
        finally:
            await conn.close()

    # ============================================================
    # ✅ SUPPRIMER UNE ZONE - AVEC SUPPRESSION DES NOTIFICATIONS
    # ============================================================
    async def supprimer_zone(self, id_zone: int, user_id: int) -> bool:
        """
        Supprime une zone et toutes les notifications liées
        Retourne True si supprimée, False si non trouvée
        """
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            # Vérifier que la zone appartient à l'utilisateur
            row = await conn.fetchrow(
                "SELECT id_zone FROM zone_infectee WHERE id_zone = $1 AND id_utilisateur = $2",
                id_zone, user_id
            )
            if not row:
                return False
            
            # ✅ 1. Supprimer les notifications liées à cette zone
            await conn.execute(
                "DELETE FROM notification WHERE id_zone = $1",
                id_zone
            )
            print(f"🗑️ Notifications liées à la zone #{id_zone} supprimées")
            
            # ✅ 2. Supprimer la zone
            await conn.execute("DELETE FROM zone_infectee WHERE id_zone = $1", id_zone)
            print(f"🗑️ Zone #{id_zone} supprimée (utilisateur: {user_id})")
            return True
        finally:
            await conn.close()
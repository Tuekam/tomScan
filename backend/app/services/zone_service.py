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

    def distance_en_mètres(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Formule de Haversine pour calculer la distance entre deux points GPS"""
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
                WHERE ST_Contains(
                    polygone, 
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)
                )
                LIMIT 1
            """, lon, lat)
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

    async def regrouper_observations_avec_parcelles(self, nouvelle_obs: dict, id_utilisateur: int = 1):
        """Regroupe les observations et détermine les parcelles concernées"""
        
        # 1. Récupérer les observations existantes proches
        observations_proches = await self.obs_repo.get_observations_proches(
            nouvelle_obs["latitude"], 
            nouvelle_obs["longitude"], 
            rayon_m=settings.RAYON_GROUPEMENT_M
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
        
        # 3. Si on a assez d'observations, créer ou mettre à jour une zone
        if len(toutes_obs) >= settings.SEUIL_CREATION_ZONE:
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
            
            # Vérifier si une zone existe déjà
            id_existant = await self.zone_repo.zone_existe_proche(
                centre_lat, centre_lon, settings.RAYON_RECHERCHE_ZONE
            )
            
            if id_existant:
                # Mettre à jour la zone existante
                zone_actuelle = await self.zone_repo.get_zone_by_id(id_existant)
                if zone_actuelle:
                    nouveau_total = zone_actuelle["nombre_observations"] + len(toutes_obs)
                    await self.zone_repo.mettre_a_jour_zone_simple(
                        id_existant, 
                        nouveau_total, 
                        centre_lat, 
                        centre_lon, 
                        zone_type
                    )
                id_zone = id_existant
                print(f"🔄 Zone #{id_existant} mise à jour (total: {nouveau_total} observations)")
            else:
                # ✅ Créer une nouvelle zone AVEC les observations (pour le rayon dynamique)
                id_zone = await self.zone_repo.creer_zone(
                    centre_lat=centre_lat,
                    centre_lon=centre_lon,
                    nombre_obs=len(toutes_obs),
                    observations=toutes_obs,  # ← Passer les observations
                    id_parcelle=id_parcelle,
                    zone_type=zone_type,
                    id_utilisateur=id_utilisateur
                )
                print(f"🆕 Nouvelle zone #{id_zone} créée ({zone_type})")
            
            # Créer une notification
            maladies = {}
            for obs in toutes_obs:
                m = obs.get("maladie", "Inconnue")
                maladies[m] = maladies.get(m, 0) + 1
            
            await self.creer_notification_zone(
                id_utilisateur=id_utilisateur,
                id_zone=id_zone,
                id_parcelle=id_parcelle,
                centre_lat=centre_lat,
                centre_lon=centre_lon,
                observations=len(toutes_obs),
                maladies=maladies
            )
            
            return {
                "zone_creee": True,
                "id_zone": id_zone,
                "zone_type": zone_type,
                "id_parcelle": id_parcelle,
                "parcelles_concernees": list(parcelles_concernees)
            }
        
        return {"zone_creee": False, "raison": f"Seulement {len(toutes_obs)} observations (seuil {settings.SEUIL_CREATION_ZONE})"}

    async def creer_notification_zone(
        self,
        id_utilisateur: int,
        id_zone: int,
        id_parcelle: int | None,
        centre_lat: float,
        centre_lon: float,
        observations: int,
        maladies: dict
    ):
        """Crée une notification pour une nouvelle zone"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            if observations >= 20:
                titre = "🚨 Zone critique détectée !"
                message = f"Une zone infectée critique a été détectée avec {observations} observations. Intervention immédiate recommandée."
                type_notif = "zone_critique"
            elif observations >= 10:
                titre = "⚠️ Zone active détectée"
                message = f"Une zone infectée active a été détectée avec {observations} observations. Traitement recommandé."
                type_notif = "zone_creee"
            else:
                titre = "📍 Nouvelle zone émergente"
                message = f"Une nouvelle zone infectée émergente a été détectée avec {observations} observations. Surveillance recommandée."
                type_notif = "zone_creee"
            
            # Maladie dominante
            maladie_dominante = max(maladies, key=maladies.get) if maladies else "Inconnue"
            maladie_dominante = maladie_dominante.replace('Tomato_', '').replace('_', ' ')
            message = f"{message} Maladie dominante: {maladie_dominante}."
            
            await conn.execute("""
                INSERT INTO notification 
                    (id_utilisateur, titre, message, type, id_zone, id_parcelle, latitude, longitude)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """, id_utilisateur, titre, message, type_notif, id_zone, id_parcelle, centre_lat, centre_lon)
            print(f"🔔 Notification créée: {titre}")
        finally:
            await conn.close()

    async def get_zones_utilisateur(self, id_utilisateur: int) -> list[dict]:
        """Récupère toutes les zones d'un utilisateur"""
        return await self.zone_repo.get_zones_by_user(id_utilisateur)

    async def get_zone_detail(self, id_zone: int) -> dict | None:
        """Récupère les détails d'une zone avec ses observations"""
        zone = await self.zone_repo.get_zone_by_id(id_zone)
        if not zone:
            return None
        
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            observations = await conn.fetch("""
                SELECT 
                    o.id_observation,
                    o.latitude,
                    o.longitude,
                    o.maladie_nom,
                    o.confiance,
                    o.timestamp
                FROM observation o
                WHERE ST_DWithin(
                    ST_SetSRID(ST_MakePoint(o.longitude, o.latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                    $3
                )
                ORDER BY o.timestamp DESC
            """, zone["centre_longitude"], zone["centre_latitude"], zone["rayon"])
            
            return {
                **zone,
                "observations": [dict(obs) for obs in observations]
            }
        finally:
            await conn.close()
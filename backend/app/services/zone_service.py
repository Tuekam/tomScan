# backend/app/services/realtime_service.py
import cv2
import numpy as np
import asyncpg
from app.core.config import settings
from datetime import datetime
from math import radians, sin, cos, sqrt, atan2
from typing import List, Tuple
from app.core.config import settings


class RealtimeSession:
    """Gestion d'une session de scan temps réel"""
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.start_time = datetime.now()
        self.last_frame_time = 0
        self.positions_scannees: List[Tuple[float, float, datetime]] = []
        self.observations: List[dict] = []
        
        # Statistiques
        self.total_frames = 0
        self.frames_analysees = 0
        self.frames_ignored_rate = 0
        self.frames_ignored_quality = 0
        self.frames_ignored_gps = 0
    
    @staticmethod
    def distance_en_metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Distance entre deux points GPS (Haversine)"""
        R = 6371000
        phi1 = radians(lat1)
        phi2 = radians(lat2)
        dphi = radians(lat2 - lat1)
        dlambda = radians(lon2 - lon1)
        a = sin(dphi/2)**2 + cos(phi1) * cos(phi2) * sin(dlambda/2)**2
        return R * 2 * atan2(sqrt(a), sqrt(1-a))
    
    @staticmethod
    def qualite_image(image_bytes: bytes) -> float:
        """Score de netteté (0-100)"""
        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
            if img is None:
                return 0
            laplacian_var = cv2.Laplacian(img, cv2.CV_64F).var()
            return min(100, max(0, laplacian_var / 10))
        except Exception:
            return 0
    
    def get_rayon_dedoublonnage(self, precision_gps: float) -> float:
        """
        Retourne le rayon de dédoublonnage en fonction de la précision GPS.
        Utilise les valeurs de settings.
        """
        if precision_gps <= 10.0:
            return settings.RAYON_DEDOUBLONNAGE_GPS_PRECIS
        elif precision_gps <= 20.0:
            return settings.RAYON_DEDOUBLONNAGE_GPS_MOYEN
        elif precision_gps <= 50.0:
            return settings.RAYON_DEDOUBLONNAGE_GPS_IMPRECIS
        else:
            return settings.RAYON_DEDOUBLONNAGE_GPS_TRES_IMPRECIS
    
    def doit_analyser_frame(self, lat: float, lon: float, current_time: float, 
                            image_bytes: bytes, precision_gps: float = 5.0,
                            qualite_min: float = None) -> Tuple[bool, str]:
        """
        Vérifie si une frame doit être analysée.
        Utilise les valeurs de settings pour les seuils.
        """
        if qualite_min is None:
            qualite_min = settings.QUALITE_IMAGE_MIN
        
        self.total_frames += 1
        
        # 1. Vérifier le taux (utilise settings.FPS_CIBLE)
        interval_min = 1.0 / settings.FPS_CIBLE
        if current_time - self.last_frame_time < interval_min:
            self.frames_ignored_rate += 1
            return False, "rate_limit"
        
        # 2. Vérifier la qualité de l'image
        qualite = self.qualite_image(image_bytes)
        if qualite < qualite_min:
            self.frames_ignored_quality += 1
            return False, "poor_quality"
        
        # 3. Vérifier si la position a déjà été scannée (rayon adaptatif)
        rayon = self.get_rayon_dedoublonnage(precision_gps)
        
        for (lat2, lon2, _) in self.positions_scannees:
            distance = self.distance_en_metres(lat, lon, lat2, lon2)
            if distance <= rayon:
                self.frames_ignored_gps += 1
                return False, "already_scanned"
        
        # 4. Ajouter la position immédiatement pour éviter les doublons
        self.positions_scannees.append((lat, lon, datetime.now()))
        
        return True, "ok"
    
    def ajouter_analyse(self, lat: float, lon: float, maladie: str, confiance: float, 
                        id_observation: int = None, id_diagnostic: int = None):
        """Ajoute une observation à la session"""
        now = datetime.now()
        self.last_frame_time = now.timestamp()
        self.frames_analysees += 1
        
        self.observations.append({
            "latitude": lat,
            "longitude": lon,
            "maladie": maladie,
            "confiance": confiance,
            "id_observation": id_observation,
            "id_diagnostic": id_diagnostic,
            "timestamp": now.isoformat()
        })
    
    def get_resume(self) -> dict:
        """Génère un résumé détaillé de la session"""
        duree = (datetime.now() - self.start_time).total_seconds()
        
        taux_analyse = 0
        if self.total_frames > 0:
            taux_analyse = (self.frames_analysees / self.total_frames) * 100
        
        # Statistiques par maladie
        maladies_stats = {}
        for obs in self.observations:
            m = obs.get("maladie", "Inconnue")
            maladies_stats[m] = maladies_stats.get(m, 0) + 1
        
        # Regrouper les observations en zones (utilise settings)
        zones = self._regrouper_observations()
        
        return {
            "session_id": self.session_id,
            "duree_secondes": round(duree, 1),
            "total_frames": self.total_frames,
            "frames_analysees": self.frames_analysees,
            "taux_analyse": round(taux_analyse, 1),
            "frames_ignored_rate": self.frames_ignored_rate,
            "frames_ignored_quality": self.frames_ignored_quality,
            "frames_ignored_gps": self.frames_ignored_gps,
            "maladies_stats": maladies_stats,
            "total_observations": len(self.observations),
            "zones": zones
        }
    
    def _regrouper_observations(self) -> List[dict]:
        """Regroupe les observations en zones (utilise settings)"""
        if not self.observations:
            return []
        
        rayon = settings.RAYON_GROUPEMENT_M
        seuil = settings.SEUIL_CREATION_ZONE
        
        groupes = []
        observations_restantes = self.observations.copy()
        
        while observations_restantes:
            obs = observations_restantes.pop(0)
            groupe = [obs]
            i = 0
            while i < len(observations_restantes):
                if self.distance_en_metres(
                    obs["latitude"], obs["longitude"],
                    observations_restantes[i]["latitude"], observations_restantes[i]["longitude"]
                ) <= rayon:
                    groupe.append(observations_restantes.pop(i))
                else:
                    i += 1
            
            if len(groupe) >= seuil:
                centre_lat = sum(o["latitude"] for o in groupe) / len(groupe)
                centre_lon = sum(o["longitude"] for o in groupe) / len(groupe)
                maladies = {}
                for o in groupe:
                    m = o.get("maladie", "Inconnue")
                    maladies[m] = maladies.get(m, 0) + 1
                
                groupes.append({
                    "centre_lat": centre_lat,
                    "centre_lon": centre_lon,
                    "observations": len(groupe),
                    "maladies": maladies
                })
        
        return 
    

async def creer_notification(
    id_utilisateur: int,
    titre: str,
    message: str,
    type: str,
    id_zone: int = None,
    id_parcelle: int = None,
    latitude: float = None,
    longitude: float = None
):
    """Crée une notification pour l'utilisateur"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        await conn.execute("""
            INSERT INTO notification 
                (id_utilisateur, titre, message, type, id_zone, id_parcelle, latitude, longitude)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        """, id_utilisateur, titre, message, type, id_zone, id_parcelle, latitude, longitude)
    finally:
        await conn.close()
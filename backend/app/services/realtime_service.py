# backend/app/services/realtime_service.py
import cv2
import numpy as np
from datetime import datetime
from math import radians, sin, cos, sqrt, atan2
from typing import List, Tuple
from app.core.config import settings

class RealtimeSession:
    """Gestion d'une session de scan temps réel"""
    
    def __init__(self, session_id: str, user_id: int = 1):
        self.session_id = session_id
        self.user_id = user_id 
        self.start_time = datetime.now()
        self.last_frame_time = 0
        self.observations: List[dict] = []
        
        # Statistiques
        self.total_frames = 0
        self.frames_analysees = 0
        self.frames_ignored_rate = 0
        self.frames_ignored_quality = 0
    
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
        """
        Score de netteté (0-100)
        ✅ Version tolérante pour le temps réel
        """
        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
            if img is None:
                return 50
            
            laplacian_var = cv2.Laplacian(img, cv2.CV_64F).var()
            score = min(100, max(0, laplacian_var / 5))
            return score
        except Exception:
            return 50
    
    def doit_analyser_frame(self, lat: float, lon: float, current_time: float, 
                            image_bytes: bytes, precision_gps: float = 5.0) -> Tuple[bool, str]:
        """
        Vérifie si une frame doit être analysée.
        ✅ Filtre FPS + Qualité uniquement
        ✅ Plus de dédoublonnage GPS
        """
        self.total_frames += 1
        
        # 1. Vérifier le taux (FPS max)
        intervalle_min = 1.0 / settings.FPS_CIBLE
        if current_time - self.last_frame_time < intervalle_min:
            self.frames_ignored_rate += 1
            return False, "rate_limit"
        
        # 2. Vérifier la qualité de l'image
        qualite = self.qualite_image(image_bytes)
        if qualite < settings.QUALITE_IMAGE_MIN:
            self.frames_ignored_quality += 1
            return False, "poor_quality"
        
        return True, "ok"
    
    # ============================================================
    # ✅ CORRIGÉ : ajouter_analyse avec id_parcelle
    # ============================================================
    def ajouter_analyse(self, lat: float, lon: float, maladie: str, confiance: float, 
                        id_observation: int = None, id_diagnostic: int = None,
                        id_parcelle: int = None):
        """Ajoute une observation à la session avec sa parcelle"""
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
            "id_parcelle": id_parcelle,  # ← AJOUTÉ
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
        
        # Regrouper les observations en zones
        zones = self._regrouper_observations()
        
        return {
            "session_id": self.session_id,
            "duree_secondes": round(duree, 1),
            "total_frames": self.total_frames,
            "frames_analysees": self.frames_analysees,
            "taux_analyse": round(taux_analyse, 1),
            "frames_ignored_rate": self.frames_ignored_rate,
            "frames_ignored_quality": self.frames_ignored_quality,
            "maladies_stats": maladies_stats,
            "total_observations": len(self.observations),
            "zones": zones
        }
    
    def _regrouper_observations(self) -> List[dict]:
        """
        Regroupe les observations en zones avec un rayon adaptatif.
        ✅ Utilise settings.RAYON_GROUPEMENT_M et settings.SEUIL_CREATION_ZONE
        ✅ Retourne les observations individuelles pour le rayon dynamique
        ✅ CORRIGÉ : Vérifie la distance avec TOUTES les observations du groupe
        """
        if not self.observations:
            return []
        
        rayon_regroupement = settings.RAYON_GROUPEMENT_M
        seuil_creation = settings.SEUIL_CREATION_ZONE
        
        print(f"   🔄 Regroupement: {len(self.observations)} observations, rayon={rayon_regroupement}m, seuil={seuil_creation}")
        
        groupes = []
        observations_restantes = self.observations.copy()
        
        while observations_restantes:
            premiere = observations_restantes.pop(0)
            groupe = [premiere]
            
            i = 0
            while i < len(observations_restantes):
                obs = observations_restantes[i]
                proche = False
                # ✅ Vérifier la distance avec TOUTES les observations du groupe
                for membre in groupe:
                    if self.distance_en_metres(
                        obs["latitude"], obs["longitude"],
                        membre["latitude"], membre["longitude"]
                    ) <= rayon_regroupement:
                        proche = True
                        break
                if proche:
                    groupe.append(observations_restantes.pop(i))
                    i = 0  # Redémarrer pour vérifier les nouvelles connexions
                else:
                    i += 1
            
            print(f"   📊 Groupe trouvé: {len(groupe)} observations")
            
            if len(groupe) >= seuil_creation:
                centre_lat = sum(o["latitude"] for o in groupe) / len(groupe)
                centre_lon = sum(o["longitude"] for o in groupe) / len(groupe)
                maladies = {}
                for o in groupe:
                    m = o.get("maladie", "Inconnue")
                    maladies[m] = maladies.get(m, 0) + 1
                
                # ✅ Ajouter les parcelles
                parcelles = {}
                for o in groupe:
                    p = o.get("id_parcelle")
                    if p:
                        parcelles[p] = parcelles.get(p, 0) + 1
                
                groupes.append({
                    "centre_lat": centre_lat,
                    "centre_lon": centre_lon,
                    "observations": len(groupe),
                    "maladies": maladies,
                    "parcelles": parcelles,  # ← AJOUTÉ
                    "observations_list": groupe
                })
                print(f"   ✅ Zone créée: {len(groupe)} observations")
            else:
                print(f"   ⏭️ Groupe ignoré: {len(groupe)} < {seuil_creation}")
        
        print(f"   🏁 Total zones: {len(groupes)}")
        return groupes
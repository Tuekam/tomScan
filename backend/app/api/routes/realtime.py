from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Query
from datetime import datetime
import uuid
import json
import cv2
import numpy as np
import asyncpg
from ultralytics import YOLO
from app.services.realtime_service import RealtimeSession
from app.services.ia_service import IAService
from app.repositories.diagnostic_repository import DiagnosticRepository
from app.repositories.observation_repository import ObservationRepository
from app.repositories.maladie_repository import MaladieRepository
from app.repositories.zone_repository import ZoneRepository
from app.core.config import settings

router = APIRouter()

# Services
ia_service = IAService(settings.MODEL_PATH)
diag_repo = DiagnosticRepository()
obs_repo = ObservationRepository()
maladie_repo = MaladieRepository()
zone_repo = ZoneRepository()

# YOLO pour la détection de présence
YOLO_MODEL_PATH = settings.YOLO_MODEL_PATH
SEUIL_CONFIANCE_YOLO = settings.SEUIL_CONFIANCE_YOLO
SEUIL_CONFIANCE_RESNET = settings.SEUIL_CONFIANCE_RESNET

print(f"📦 YOLO Model: {YOLO_MODEL_PATH}")
print(f"📦 Seuil YOLO: {SEUIL_CONFIANCE_YOLO}")
print(f"📦 Seuil ResNet: {SEUIL_CONFIANCE_RESNET}")

yolo_model = YOLO(YOLO_MODEL_PATH)

# Stockage des sessions
sessions = {}
TIMEOUT_SECONDS = settings.TIMEOUT_SESSION_SECONDS

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================

def get_bbox_color(maladie: str) -> str:
    """Couleur associée à la maladie pour les bounding boxes"""
    colors = {
        "Tomato_healthy": "#22C55E",
        "Tomato_Early_Blight": "#F59E0B",
        "Tomato_Late_blight": "#EF4444",
        "Tomato_leaf_yellow_curl_virus": "#8B5CF6",
        "Tomato_mold": "#EC4899",
        "Tomato_Septoria_leaf_spot": "#6366F1",
        "Non identifiable": "#6B7280"
    }
    return colors.get(maladie, "#6B7280")

async def contient_plante(image_bytes: bytes) -> bool:
    """
    ✅ VERSION CORRIGÉE : Filtre binaire comme dans predict.py
    Retourne True si YOLO détecte au moins une plante/feuille de tomate
    """
    try:
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        results = yolo_model(img, verbose=False)
        
        for r in results:
            if r.boxes is not None:
                for box in r.boxes:
                    if box.conf.item() >= SEUIL_CONFIANCE_YOLO:
                        print(f"   🎯 YOLO: plante détectée (conf: {box.conf.item():.2f})")
                        return True
        return False
    except Exception as e:
        print(f"   ❌ Erreur YOLO: {e}")
        return False

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
        print(f"🔔 Notification créée: {titre}")
    finally:
        await conn.close()

# ============================================================
# ROUTES
# ============================================================

@router.post("/realtime/start")
async def start_realtime_session(user_id: int = Query(...)):
    """Démarre une nouvelle session temps réel"""
    session_id = str(uuid.uuid4())
    sessions[session_id] = RealtimeSession(session_id, user_id)
    print(f"🎬 Session temps réel démarrée: {session_id} (utilisateur: {user_id})")
    return {"session_id": session_id}

@router.post("/realtime/{session_id}/frame")
async def process_frame(
    session_id: str,
    image: UploadFile = File(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
    precision_gps: float = Form(5.0)
):
    """
    ✅ VERSION CORRIGÉE : Alignée sur la logique du mode photo
    1. YOLO = Filtre de présence (comme predict.py)
    2. ResNet = Classification de l'image entière (comme predict.py)
    3. Pas de découpe YOLO, pas de rejet "trop grand"
    """
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session invalide ou expirée")
    
    session = sessions[session_id]
    current_time = datetime.now().timestamp()
    image_bytes = await image.read()
    
    print(f"📍 FRAME #{session.total_frames + 1} -> Lat: {latitude:.6f}, Lon: {longitude:.6f}, Précision: {precision_gps:.1f}m")
    
    # ============================================================
    # 1. FILTRE : TAUX (FPS)
    # ============================================================
    doit_analyser, raison = session.doit_analyser_frame(
        latitude, longitude, current_time, image_bytes, precision_gps
    )
    
    if not doit_analyser:
        print(f"   ⏭️ Frame ignorée: {raison}")
        return {
            "status": "ignored",
            "reason": raison,
            "message": "Frame ignorée"
        }
    
    # ============================================================
    # 2. YOLO = FILTRE DE PRÉSENCE (comme predict.py)
    # ============================================================
    if not await contient_plante(image_bytes):
        print(f"   ❌ Aucune plante de tomate détectée (YOLO)")
        return {
            "status": "ignored",
            "reason": "no_plant",
            "message": "Aucune plante de tomate détectée"
        }
    
    # ============================================================
    # 3. RESNET = CLASSIFICATION DE L'IMAGE ENTIÈRE (comme predict.py)
    # ============================================================
    try:
        maladie, confiance = await ia_service.classifier(image_bytes)
        
        print(f"   🧠 ResNet: {maladie} ({confiance:.1f}%)")
        
        if maladie == "Non identifiable" or confiance < SEUIL_CONFIANCE_RESNET:
            print(f"   ❌ Rejeté: {maladie} ({confiance:.1f}%) < seuil {SEUIL_CONFIANCE_RESNET}")
            return {
                "status": "ignored",
                "reason": "low_confidence",
                "message": f"Confiance trop faible: {confiance:.1f}%"
            }
        
        # ============================================================
        # 4. SUCCÈS ! SAUVEGARDE
        # ============================================================
        print(f"   ✅ ANALYSÉE: {maladie} ({confiance:.1f}%)")
        
        # Sauvegarder le diagnostic
        id_diagnostic = await diag_repo.save_diagnostic(session.user_id, "TEMPS_REEL", None)
        id_maladie = await maladie_repo.get_id_by_nom(maladie)
        now = datetime.now()
        
        # Sauvegarder l'observation
        id_observation = await obs_repo.save_observation(
            id_diagnostic=id_diagnostic,
            id_maladie=id_maladie,
            timestamp=now,
            latitude=latitude,
            longitude=longitude,
            precision_gps=precision_gps,
            image_path="",
            confiance=confiance,
            maladie_nom=maladie,
            id_parcelle=None
        )
        
        # Ajouter à la session pour regroupement
        session.ajouter_analyse(
            latitude, longitude, maladie, confiance,
            id_observation, id_diagnostic
        )
        
        # ============================================================
        # 5. BOUNDING BOXES (optionnel - pour l'affichage uniquement)
        # ============================================================
        # On peut toujours renvoyer des bounding boxes pour l'affichage
        # même si ResNet analyse l'image entière
        detections = []
        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            results = yolo_model(img, verbose=False)
            
            for r in results:
                if r.boxes is not None:
                    for box in r.boxes:
                        if box.conf.item() >= SEUIL_CONFIANCE_YOLO:
                            x1, y1, x2, y2 = box.xyxy[0].tolist()
                            w = x2 - x1
                            h = y2 - y1
                            # ✅ Plus de filtres restrictifs pour l'affichage
                            detections.append({
                                "maladie": maladie,  # ← On met la maladie ResNet
                                "confiance": round(confiance, 2),
                                "x": int(x1),
                                "y": int(y1),
                                "width": int(w),
                                "height": int(h),
                                "bbox_color": get_bbox_color(maladie)
                            })
                            break  # ← Une seule boîte suffit pour l'affichage
        except Exception as e:
            print(f"   ⚠️ Erreur bounding boxes: {e}")
        
        return {
            "status": "analyzed",
            "maladie": maladie,
            "confiance": round(confiance, 2),
            "id_observation": id_observation,
            "id_diagnostic": id_diagnostic,
            "detections": detections,  # ← Pour l'affichage uniquement
            "position": {"lat": latitude, "lon": longitude}
        }
            
    except Exception as e:
        print(f"   ❌ Erreur analyse: {e}")
        import traceback
        traceback.print_exc()
        return {
            "status": "error",
            "reason": str(e)
        }

@router.post("/realtime/{session_id}/end")
async def end_realtime_session(
    session_id: str,
    user_id: int = Query(...)
):
    """Termine la session et sauvegarde le résumé en base"""
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session invalide")
    
    session = sessions[session_id]
    resume = session.get_resume()
    
    final_user_id = user_id if user_id else session.user_id
    
    print(f"\n📊 RÉSUMÉ DE LA SESSION #{session_id[:8]}")
    print(f"   📸 Frames totales: {resume['total_frames']}")
    print(f"   ✅ Frames analysées: {resume['frames_analysees']}")
    print(f"   ⏭️ Ignorées (rate): {resume['frames_ignored_rate']}")
    print(f"   📷 Ignorées (qualité): {resume['frames_ignored_quality']}")
    
    zones_crees = []
    for zone_data in resume["zones"]:
        zone_type = "HORS_PARCELLE"
        
        id_zone = await zone_repo.creer_zone(
            centre_lat=zone_data["centre_lat"],
            centre_lon=zone_data["centre_lon"],
            nombre_obs=zone_data["observations"],
            id_parcelle=None,
            zone_type=zone_type,
            id_utilisateur=final_user_id
        )
        
        nb_obs = zone_data["observations"]
        if nb_obs >= 20:
            titre = f"🚨 Zone critique détectée !"
            message = f"Une zone infectée critique a été détectée avec {nb_obs} observations. Intervention immédiate recommandée."
            type_notif = "zone_critique"
        elif nb_obs >= 10:
            titre = f"⚠️ Zone active détectée"
            message = f"Une zone infectée active a été détectée avec {nb_obs} observations. Traitement recommandé."
            type_notif = "zone_creee"
        else:
            titre = f"📍 Nouvelle zone émergente"
            message = f"Une nouvelle zone infectée émergente a été détectée avec {nb_obs} observations. Surveillance recommandée."
            type_notif = "zone_creee"
        
        maladies_list = zone_data.get("maladies", {})
        if maladies_list:
            maladie_dominante = max(maladies_list, key=maladies_list.get) if maladies_list else "Inconnue"
            maladie_dominante = maladie_dominante.replace('Tomato_', '').replace('_', ' ')
            message = f"{message} Maladie dominante: {maladie_dominante}."
        
        await creer_notification(
            id_utilisateur=final_user_id,
            titre=titre,
            message=message,
            type=type_notif,
            id_zone=id_zone,
            latitude=zone_data["centre_lat"],
            longitude=zone_data["centre_lon"]
        )
        
        zones_crees.append({
            "id_zone": id_zone,
            "observations": zone_data["observations"],
            "maladies": zone_data["maladies"]
        })
    
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        table_exists = await conn.fetchval("""
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables 
                WHERE table_name = 'session'
            )
        """)
        
        if table_exists:
            await conn.execute("""
                INSERT INTO session 
                    (id_utilisateur, date_debut, date_fin, mode, total_frames, frames_analysees, zones_crees, resume)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """, final_user_id, session.start_time, datetime.now(), "TEMPS_REEL",
                resume["total_frames"], resume["frames_analysees"], len(zones_crees),
                json.dumps({
                    "maladies_stats": resume["maladies_stats"],
                    "zones": zones_crees,
                    "total_observations": resume["total_observations"],
                    "duree_secondes": resume["duree_secondes"]
                })
            )
            print(f"💾 Session #{session_id[:8]} sauvegardée en base")
        else:
            print("⚠️ Table 'session' non trouvée, skip sauvegarde")
            
    except Exception as e:
        print(f"❌ Erreur sauvegarde session: {e}")
    finally:
        await conn.close()
    
    del sessions[session_id]
    
    return {
        "status": "completed",
        "resume": resume,
        "zones_crees": zones_crees
    }

@router.get("/realtime/{session_id}/status")
async def get_session_status(session_id: str):
    """État de la session en cours"""
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session invalide ou expirée")
    
    session = sessions[session_id]
    return {
        "session_id": session_id,
        "total_frames": session.total_frames,
        "frames_analysees": session.frames_analysees,
        "frames_ignored_rate": session.frames_ignored_rate,
        "frames_ignored_quality": session.frames_ignored_quality,
        "observations": len(session.observations)
    }
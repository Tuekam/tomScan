# backend/app/api/routes/realtime.py
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
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

# YOLO pour les bounding boxes (utilise settings)
yolo_model = YOLO(settings.YOLO_MODEL_PATH)

# Stockage des sessions
sessions = {}
TIMEOUT_SECONDS = settings.TIMEOUT_SESSION_SECONDS

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

@router.post("/realtime/start")
async def start_realtime_session():
    """Démarre une nouvelle session temps réel"""
    session_id = str(uuid.uuid4())
    sessions[session_id] = RealtimeSession(session_id)
    print(f"🎬 Session temps réel démarrée: {session_id}")
    return {"session_id": session_id}

@router.post("/realtime/{session_id}/frame")
async def process_frame(
    session_id: str,
    image: UploadFile = File(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
    precision_gps: float = Form(5.0)
):
    """Reçoit et analyse une frame avec détection des plantes"""
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session invalide ou expirée")
    
    session = sessions[session_id]
    current_time = datetime.now().timestamp()
    image_bytes = await image.read()
    
    print(f"📍 FRAME #{session.total_frames + 1} -> Lat: {latitude:.6f}, Lon: {longitude:.6f}, Précision: {precision_gps:.1f}m")
    
    # Vérifier si la frame doit être analysée (utilise settings pour qualite_min)
    doit_analyser, raison = session.doit_analyser_frame(
        latitude, longitude, current_time, image_bytes, precision_gps, settings.QUALITE_IMAGE_MIN
    )
    
    if not doit_analyser:
        print(f"   ⏭️ Frame ignorée: {raison}")
        return {
            "status": "ignored",
            "reason": raison,
            "message": "Frame ignorée"
        }
    
    # --- Analyse avec YOLO ---
    try:
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        results = yolo_model(img, verbose=False)
        detections = []
        
        for r in results:
            if r.boxes is not None:
                for box in r.boxes:
                    if box.conf.item() >= settings.SEUIL_CONFIANCE_YOLO:
                        x1, y1, x2, y2 = box.xyxy[0].tolist()
                        w = x2 - x1
                        h = y2 - y1
                        
                        # Filtres : ignorer les détections trop petites ou trop grandes
                        if w < 30 or h < 30:
                            continue
                        if w > img.shape[1] * 0.8 or h > img.shape[0] * 0.8:
                            continue
                        
                        # Rapport d'aspect d'une feuille de tomate (~0.5 à 1.8)
                        aspect_ratio = w / h
                        if aspect_ratio < 0.3 or aspect_ratio > 2.5:
                            continue
                        
                        plant_img = img[int(y1):int(y2), int(x1):int(x2)]
                        _, plant_bytes = cv2.imencode('.jpg', plant_img)
                        
                        maladie, confiance = await ia_service.classifier(plant_bytes.tobytes())
                        
                        # Ignorer si ResNet retourne "Non identifiable" ou confiance trop faible
                        if maladie == "Non identifiable" or confiance < 30.0:
                            continue
                        
                        detections.append({
                            "maladie": maladie,
                            "confiance": round(confiance, 2),
                            "x": int(x1),
                            "y": int(y1),
                            "width": int(w),
                            "height": int(h),
                            "bbox_color": get_bbox_color(maladie)
                        })
        
        if detections:
            detection_principale = detections[0]
            maladie = detection_principale["maladie"]
            confiance = detection_principale["confiance"]
            
            print(f"   ✅ ANALYSÉE: {maladie} ({confiance:.1f}%)")
            
            id_diagnostic = await diag_repo.save_diagnostic(1, "TEMPS_REEL", None)
            id_maladie = await maladie_repo.get_id_by_nom(maladie)
            now = datetime.now()
            
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
            
            session.ajouter_analyse(
                latitude, longitude, maladie, confiance,
                id_observation, id_diagnostic
            )
            
            return {
                "status": "analyzed",
                "maladie": maladie,
                "confiance": round(confiance, 2),
                "id_observation": id_observation,
                "detections": detections,
                "position": {"lat": latitude, "lon": longitude}
            }
        else:
            print(f"   ❌ Aucune plante détectée")
            return {
                "status": "ignored",
                "reason": "no_plant",
                "message": "Aucune plante détectée"
            }
            
    except Exception as e:
        print(f"   ❌ Erreur analyse: {e}")
        return {
            "status": "error",
            "reason": str(e)
        }

@router.post("/realtime/{session_id}/end")
async def end_realtime_session(session_id: str, user_id: int = 1):
    """Termine la session et sauvegarde le résumé en base"""
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session invalide")
    
    session = sessions[session_id]
    resume = session.get_resume()
    
    print(f"\n📊 RÉSUMÉ DE LA SESSION #{session_id[:8]}")
    print(f"   📸 Frames totales: {resume['total_frames']}")
    print(f"   ✅ Frames analysées: {resume['frames_analysees']}")
    print(f"   ⏭️ Ignorées (rate): {resume['frames_ignored_rate']}")
    print(f"   📷 Ignorées (qualité): {resume['frames_ignored_quality']}")
    print(f"   📍 Ignorées (doublon GPS): {resume['frames_ignored_gps']}")
    
    zones_crees = []
    for zone_data in resume["zones"]:
        id_zone = await zone_repo.creer_zone(
            centre_lat=zone_data["centre_lat"],
            centre_lon=zone_data["centre_lon"],
            nombre_obs=zone_data["observations"],
            id_parcelle=None,
            zone_type="HORS_PARCELLE"
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
            """, user_id, session.start_time, datetime.now(), "TEMPS_REEL",
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
        "frames_ignored_gps": session.frames_ignored_gps,
        "observations": len(session.observations)
    }
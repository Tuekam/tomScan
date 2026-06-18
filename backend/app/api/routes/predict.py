# backend/app/api/routes/predict.py
from fastapi import APIRouter, UploadFile, File, Form
from datetime import datetime
from math import radians, sin, cos, sqrt, atan2
import os
import uuid
import cv2
import numpy as np
import asyncpg
from ultralytics import YOLO
from app.services.ia_service import IAService
from app.repositories.diagnostic_repository import DiagnosticRepository
from app.repositories.observation_repository import ObservationRepository
from app.repositories.maladie_repository import MaladieRepository
from app.repositories.zone_repository import ZoneRepository
from app.core.config import settings

router = APIRouter()

# Initialisation des services IA
ia_service = IAService(settings.MODEL_PATH)
diag_repo = DiagnosticRepository()
obs_repo = ObservationRepository()
maladie_repo = MaladieRepository()
zone_repo = ZoneRepository()

# Chargement du modèle YOLO (utilise settings.YOLO_MODEL_PATH)
yolo_model = YOLO(settings.YOLO_MODEL_PATH)

# Règles métier depuis settings
RAYON_GROUPEMENT_M = settings.RAYON_GROUPEMENT_M
SEUIL_CREATION_ZONE = settings.SEUIL_CREATION_ZONE
RAYON_RECHERCHE_ZONE = settings.RAYON_RECHERCHE_ZONE
SEUIL_CONFIANCE_YOLO = settings.SEUIL_CONFIANCE_YOLO
UPLOAD_DIR = settings.UPLOAD_DIR

def distance_en_mètres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Formule de Haversine"""
    R = 6371000
    phi1 = radians(lat1)
    phi2 = radians(lat2)
    delta_phi = radians(lat2 - lat1)
    delta_lambda = radians(lon2 - lon1)

    a = sin(delta_phi/2)**2 + cos(phi1) * cos(phi2) * sin(delta_lambda/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c

async def contient_plante(image_bytes: bytes) -> bool:
    """Retourne True si YOLO détecte au moins une plante/feuille de tomate"""
    try:
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        results = yolo_model(img, verbose=False)
        
        for r in results:
            if r.boxes is not None:
                for box in r.boxes:
                    if box.conf.item() >= SEUIL_CONFIANCE_YOLO:
                        return True
        return False
    except Exception as e:
        print(f"Erreur YOLO : {e}")
        return False

async def trouver_parcelle_du_point(lat: float, lon: float) -> int | None:
    """Trouve la parcelle contenant ce point (géométrique)"""
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
    except Exception as e:
        print(f"Erreur trouver_parcelle_du_point: {e}")
        return None
    finally:
        await conn.close()

@router.post("/predict")
async def predict(
    image: UploadFile = File(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
    precision_gps: float = Form(0.0),
    id_parcelle: int = Form(None)
):
    # 1. Lecture de l'image
    image_bytes = await image.read()

    # Sauvegarde de l'image sur disque (utilise settings.UPLOAD_DIR)
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    extension = image.filename.split('.')[-1] if '.' in image.filename else 'jpg'
    image_filename = f"{uuid.uuid4()}.{extension}"
    image_path = os.path.join(UPLOAD_DIR, image_filename)

    with open(image_path, "wb") as f:
        f.write(image_bytes)
    
    # 2. Vérification YOLO (utilise SEUIL_CONFIANCE_YOLO)
    if not await contient_plante(image_bytes):
        return {
            "maladie": "Non identifiable",
            "confiance": 0.0,
            "message": "Aucune plante de tomate détectée",
            "description": "",
            "symptomes": "",
            "recommandation": "",
            "niveau_gravite": ""
        }
    
    # 3. Classification ResNet18
    maladie, confiance = await ia_service.classifier(image_bytes)

    # 4. Sauvegarde du diagnostic
    id_diagnostic = await diag_repo.save_diagnostic(1, "PHOTO", id_parcelle)

    # 5. Récupération de l'id de la maladie
    id_maladie = await maladie_repo.get_id_by_nom(maladie)
    
    # 6. Récupération des détails de la maladie
    details_maladie = None
    if id_maladie:
        details_maladie = await maladie_repo.get_details_by_id(id_maladie)

    # 7. Sauvegarde de l'observation
    now = datetime.now()
    id_observation = await obs_repo.save_observation(
        id_diagnostic=id_diagnostic,
        id_maladie=id_maladie,
        timestamp=now,
        latitude=latitude,
        longitude=longitude,
        precision_gps=precision_gps,
        image_path=image_path,
        confiance=confiance,
        maladie_nom=maladie,
        id_parcelle=id_parcelle
    )

    # 8. Déterminer la parcelle (si non spécifiée par l'utilisateur)
    parcelle_associee = id_parcelle
    if parcelle_associee is None:
        parcelle_associee = await trouver_parcelle_du_point(latitude, longitude)
        if parcelle_associee:
            await obs_repo.update_parcelle(id_observation, parcelle_associee)
            print(f"✅ Observation #{id_observation} associée à la parcelle #{parcelle_associee}")
        else:
            print(f"⚠️ Observation #{id_observation} hors parcelle")

    # ============================================================
    # REGROUPEMENT (utilise RAYON_GROUPEMENT_M et SEUIL_CREATION_ZONE)
    # ============================================================
    
    # 9. Trouver les observations proches de la nouvelle observation
    observations_proches = await obs_repo.get_observations_proches(
        latitude, longitude, RAYON_GROUPEMENT_M, exclude_id=id_observation
    )
    
    # 10. Ajouter la nouvelle observation au groupe
    groupe = observations_proches + [{"id_observation": id_observation, "latitude": latitude, "longitude": longitude, "id_parcelle": parcelle_associee}]
    
    zone_impactee = False
    id_zone = None
    
    # 11. Si le groupe atteint le seuil, créer ou mettre à jour une zone
    if len(groupe) >= SEUIL_CREATION_ZONE:
        # Calculer le centre de gravité
        centre_lat = sum(o["latitude"] for o in groupe) / len(groupe)
        centre_lon = sum(o["longitude"] for o in groupe) / len(groupe)
        
        # Déterminer les parcelles concernées
        parcelles_dans_groupe = set()
        for obs in groupe:
            if obs.get("id_parcelle"):
                parcelles_dans_groupe.add(obs["id_parcelle"])
        
        if len(parcelles_dans_groupe) == 1:
            id_parcelle_associee = list(parcelles_dans_groupe)[0]
            zone_type = "DANS_PARCELLE"
        elif len(parcelles_dans_groupe) > 1:
            id_parcelle_associee = None
            zone_type = "MULTI_PARCELLES"
        else:
            id_parcelle_associee = None
            zone_type = "HORS_PARCELLE"
        
        # Vérifier si une zone existe déjà à proximité (utilise RAYON_RECHERCHE_ZONE)
        id_existant = await zone_repo.zone_existe_proche(
            centre_lat, centre_lon, RAYON_RECHERCHE_ZONE
        )
        
        if id_existant:
            # Mettre à jour la zone existante
            zone_actuelle = await zone_repo.get_zone_by_id(id_existant)
            if zone_actuelle:
                nouveau_total = zone_actuelle["nombre_observations"] + 1
                await zone_repo.mettre_a_jour_zone_simple(
                    id_existant, nouveau_total, centre_lat, centre_lon, zone_type
                )
            id_zone = id_existant
            print(f"🔄 Zone #{id_existant} mise à jour (total: {nouveau_total} observations)")
        else:
            # Créer une nouvelle zone
            id_zone = await zone_repo.creer_zone(
                centre_lat, centre_lon, len(groupe), id_parcelle_associee, zone_type
            )
            print(f"🆕 Nouvelle zone #{id_zone} créée ({zone_type})")
        
        zone_impactee = True

    # 12. Construction de la réponse
    response_data = {
        "maladie": maladie,
        "confiance": round(confiance, 2),
        "id_diagnostic": id_diagnostic,
        "id_observation": id_observation,
        "latitude": latitude,
        "longitude": longitude,
        "zone_impactee": zone_impactee,
        "id_zone": id_zone,
        "id_parcelle": parcelle_associee
    }
    
    # Ajout des détails de la maladie
    if details_maladie:
        response_data["description"] = details_maladie.get("description", "")
        response_data["symptomes"] = details_maladie.get("symptomes", "")
        response_data["recommandation"] = details_maladie.get("recommandation", "")
        response_data["niveau_gravite"] = details_maladie.get("niveau_gravite", "")
    else:
        response_data["description"] = ""
        response_data["symptomes"] = ""
        response_data["recommandation"] = ""
        response_data["niveau_gravite"] = ""

    return response_data
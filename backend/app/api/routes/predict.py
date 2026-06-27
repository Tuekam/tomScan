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

# Chargement du modèle YOLO
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

def regrouper_observations(observations, rayon):
    """Regroupement par chaînage (corrigé)"""
    if not observations:
        return []
    
    groupes = []
    observations_restantes = list(observations)
    
    while observations_restantes:
        premiere = observations_restantes.pop(0)
        groupe = [premiere]
        
        i = 0
        while i < len(observations_restantes):
            obs = observations_restantes[i]
            proche = False
            for g in groupe:
                if distance_en_mètres(obs["latitude"], obs["longitude"],
                                      g["latitude"], g["longitude"]) <= rayon:
                    proche = True
                    break
            if proche:
                groupe.append(observations_restantes.pop(i))
                i = 0
            else:
                i += 1
        
        groupes.append(groupe)
    
    return groupes

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
    """Crée une notification pour l'utilisateur avec coordonnées"""
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

@router.post("/predict")
async def predict(
    image: UploadFile = File(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
    precision_gps: float = Form(0.0),
    id_parcelle: int = Form(None),
    id_utilisateur: int = Form(1)
):
    # 1. Lecture de l'image
    image_bytes = await image.read()

    # Sauvegarde de l'image sur disque (toujours)
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    extension = image.filename.split('.')[-1] if '.' in image.filename else 'jpg'
    image_filename = f"{uuid.uuid4()}.{extension}"
    image_path = os.path.join(UPLOAD_DIR, image_filename)

    with open(image_path, "wb") as f:
        f.write(image_bytes)
    
    # 2. Sauvegarde du diagnostic AVANT la vérification YOLO
    id_diagnostic = await diag_repo.save_diagnostic(id_utilisateur, "PHOTO", id_parcelle)
    
    # 3. Vérification YOLO
    if not await contient_plante(image_bytes):
        now = datetime.now()
        id_observation = await obs_repo.save_observation(
            id_diagnostic=id_diagnostic,
            id_maladie=None,
            timestamp=now,
            latitude=latitude,
            longitude=longitude,
            precision_gps=precision_gps,
            image_path=image_path,
            confiance=0.0,
            maladie_nom="Non identifiable",
            id_parcelle=id_parcelle
        )
        
        return {
            "maladie": "Non identifiable",
            "confiance": 0.0,
            "id_diagnostic": id_diagnostic,
            "id_observation": id_observation,
            "latitude": latitude,
            "longitude": longitude,
            "zone_impactee": False,
            "id_zone": None,
            "id_parcelle": id_parcelle,
            "message": "Aucune plante de tomate détectée",
            "description": "",
            "symptomes": "",
            "recommandation": "",
            "niveau_gravite": ""
        }
    
    # 4. Classification ResNet18
    maladie, confiance = await ia_service.classifier(image_bytes)

    # 5. Récupération de l'id de la maladie
    id_maladie = await maladie_repo.get_id_by_nom(maladie)
    
    # 6. Récupération des détails de la maladie
    details_maladie = None
    if id_maladie:
        details_maladie = await maladie_repo.get_details_by_id(id_maladie)

    # 7. Sauvegarde de l'observation (avec la maladie détectée)
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
    # REGROUPEMENT - VERSION AVEC AJOUT À ZONE EXISTANTE
    # ============================================================
    
    # 9. Vérifier si la nouvelle observation doit rejoindre une zone existante
    zone_proche = await zone_repo.trouver_zone_proche_observation(
        latitude, longitude, RAYON_GROUPEMENT_M
    )
    
    zone_impactee = False
    id_zone = None
    
    if zone_proche:
        # ✅ Ajouter l'observation à la zone existante
        await zone_repo.ajouter_observation_a_zone(
            zone_proche, id_observation, latitude, longitude, maladie
        )
        # ✅ Recalculer la zone
        await zone_repo.recalculer_zone(zone_proche)
        id_zone = zone_proche
        zone_impactee = True
        print(f"🔄 Observation #{id_observation} ajoutée à la zone #{zone_proche}")
    else:
        # 10. Récupérer TOUTES les observations de l'utilisateur
        toutes_obs = await obs_repo.get_observations_by_user(id_utilisateur)
        print(f"📊 Total observations pour l'utilisateur {id_utilisateur}: {len(toutes_obs)}")
        
        # 11. Regrouper par chaînage
        groupes = regrouper_observations(toutes_obs, RAYON_GROUPEMENT_M)
        print(f"📊 Groupes trouvés: {len(groupes)}")
        for i, groupe in enumerate(groupes):
            print(f"   Groupe {i+1}: {len(groupe)} observations")
        
        # 12. Pour chaque groupe, vérifier si une zone existe
        for groupe in groupes:
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
                
                # Vérifier si une zone existe déjà à proximité
                id_existant = await zone_repo.zone_existe_proche(
                    centre_lat, centre_lon, RAYON_RECHERCHE_ZONE
                )
                
                if id_existant:
                    zone_actuelle = await zone_repo.get_zone_by_id(id_existant)
                    if zone_actuelle:
                        # Mettre à jour la zone existante
                        await zone_repo.mettre_a_jour_zone_simple(
                            id_existant, len(groupe), centre_lat, centre_lon, zone_type, groupe
                        )
                    id_zone = id_existant
                    print(f"🔄 Zone #{id_existant} mise à jour (total: {len(groupe)} observations)")
                else:
                    # Créer une nouvelle zone
                    id_zone = await zone_repo.creer_zone(
                        centre_lat=centre_lat,
                        centre_lon=centre_lon,
                        nombre_obs=len(groupe),
                        observations=groupe,
                        id_parcelle=id_parcelle_associee,
                        zone_type=zone_type,
                        id_utilisateur=id_utilisateur
                    )
                    print(f"🆕 Nouvelle zone #{id_zone} créée ({zone_type}) pour l'utilisateur {id_utilisateur}")
                    
                    # Créer une notification
                    nb_obs = len(groupe)
                    if nb_obs >= 20:
                        titre = "🚨 Zone critique détectée !"
                        message = f"Une zone infectée critique a été détectée avec {nb_obs} observations. Intervention immédiate recommandée."
                        type_notif = "zone_critique"
                    elif nb_obs >= 10:
                        titre = "⚠️ Zone active détectée"
                        message = f"Une zone infectée active a été détectée avec {nb_obs} observations. Traitement recommandé."
                        type_notif = "zone_creee"
                    else:
                        titre = "📍 Nouvelle zone émergente"
                        message = f"Une nouvelle zone infectée émergente a été détectée avec {nb_obs} observations. Surveillance recommandée."
                        type_notif = "zone_creee"
                    
                    maladies_groupe = {}
                    for obs in groupe:
                        m = obs.get("maladie_nom", "Inconnue")
                        maladies_groupe[m] = maladies_groupe.get(m, 0) + 1
                    maladie_dominante = max(maladies_groupe, key=maladies_groupe.get) if maladies_groupe else "Inconnue"
                    maladie_dominante = maladie_dominante.replace('Tomato_', '').replace('_', ' ')
                    
                    await creer_notification(
                        id_utilisateur=id_utilisateur,
                        titre=titre,
                        message=f"{message} Maladie dominante: {maladie_dominante}.",
                        type=type_notif,
                        id_zone=id_zone,
                        id_parcelle=id_parcelle_associee,
                        latitude=centre_lat,
                        longitude=centre_lon
                    )
                
                zone_impactee = True
                break

    # 13. Construction de la réponse
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
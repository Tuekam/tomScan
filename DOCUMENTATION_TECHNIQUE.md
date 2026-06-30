# Documentation Technique

## 1. Aperçu du projet

TomScan est une application mobile et backend destinée à la détection des maladies de la tomate. Le projet combine :

- une API Python FastAPI pour la gestion des utilisateurs, diagnostics, observations, zones infectées, statistiques et notifications ;
- un moteur d'IA hybride qui utilise YOLO pour la détection de présence de plante/feuille et un modèle de classification ResNet pour l'identification des maladies ;
- une application mobile Flutter pour la capture d'image, le scan temps réel, la visualisation cartographique, l'historique, le chatbot et les statistiques.

Le système est conçu pour un usage terrain sur mobile, avec des fonctionnalités géospatiales et une logique métier de regroupement d'observations en zones infectées.

## 2. Architecture globale

### 2.1 Composants principaux

- `backend/`: API REST, services IA, accès base de données et logique métier.
- `backend/app/api/`: routes FastAPI exposant les endpoints du backend.
- `backend/app/core/`: configuration et connexion à la base de données.
- `backend/app/services/`: services métier (`IAService`, `RealtimeSession`, `MistralService`).
- `backend/app/repositories/`: abstractions d'accès aux entités SQL.
- `backend/ml/`: modèles et transformations.
- `mobile/`: application Flutter.
- `mobile/lib/`: code source mobile.
- `mobile/lib/screens/`: écrans de l'application.
- `mobile/lib/services/`: services mobiles (GPS, auth, base locale).
- `mobile/lib/config.dart`: configuration du backend et seuils de scan.

### 2.2 Flux des données

- L'utilisateur capture une photo dans l'app mobile.
- L'application envoie l'image et les données GPS à l'API `/api/predict`.
- Le backend vérifie la présence de plante avec YOLO puis effectue la classification avec ResNet.
- Si le diagnostic est valide, une observation est enregistrée et éventuellement regroupée en zone infectée.
- L'utilisateur peut aussi lancer un scan temps réel via `/api/realtime/*`.
- Le mobile affiche les notifications, la carte des zones, les statistiques et l'historique local.

## 3. Backend

### 3.1 Stack technique

- `FastAPI` : framework web ASGI.
- `asyncpg` : pilote PostgreSQL async.
- `uvicorn` : serveur ASGI.
- `python-multipart` : traitement des uploads de fichiers.
- `torch`, `torchvision`, `Pillow`, `opencv-python` (`cv2`) : pipeline IA.
- `ultralytics` : wrapper YOLO.
- `python-jose`, `bcrypt`, `jwt` : authentification utilisateur.
- `mistralai`, `httpx` : chatbot IA.
- `python-dotenv` : gestion des variables d'environnement.

### 3.2 Configuration

Le backend utilise `backend/app/core/config.py` pour charger les variables d'environnement via `.env`. Les paramètres clefs :

- `DATABASE_URL` : URL de connexion PostgreSQL.
- `MODEL_PATH` : modèle ResNet (`.pth`).
- `YOLO_MODEL_PATH` : modèle YOLO pour détection de plante.
- `SEUIL_CONFIANCE_YOLO` : seuil de confiance YOLO (par défaut 0.9).
- `SEUIL_CONFIANCE_RESNET` : seuil de confiance ResNet (par défaut 0.5).
- `RAYON_GROUPEMENT_M` : rayon de regroupement spatial des observations.
- `SEUIL_CREATION_ZONE` : nombre minimum d'observations pour créer une zone.
- `RAYON_RECHERCHE_ZONE` : rayon de recherche de zone.
- `TIMEOUT_SESSION_SECONDS` : durée maximale d'une session temps réel.
- `MISTRAL_API_KEY` : clé API pour le chatbot Mistral.
- `JWT_SECRET_KEY` : clé secrète pour JWT.

### 3.3 Points d'entrée API

Les routes sont enregistrées dans `backend/app/api/main.py` sous le préfixe `/api`.

Liste des principaux endpoints :

- `/api/predict` : diagnostic photo.
- `/api/realtime/start`, `/api/realtime/{session_id}/frame`, `/api/realtime/{session_id}/end`, `/api/realtime/{session_id}/status` : scan temps réel.
- `/api/zones`, `/api/zones/{id_zone}` : gestion des zones infectées.
- `/api/notifications/*` : notifications utilisateurs.
- `/api/parcelles` : gestion des parcelles.
- `/api/diagnostics` : accès aux diagnostics.
- `/api/maladies` : liste de maladies.
- `/api/chat` (`/api/conversations`, `/api/conversations/{id}/messages`) : chatbot et conversations.
- `/api/stats`, `/api/stats/zone/{id_zone}` : statistiques et détails de zone.
- `/api/auth/login`, `/api/auth/register`, `/api/auth/me` : authentification JWT.
- `/api/utilisateur/{user_id}` : profil utilisateur.
- `/api/images/{filename}` et `/api/images/profils/{filename}` : service de fichiers.

### 3.4 Modèles et services IA

#### 3.4.1 IAService

Localisé dans `backend/app/services/ia_service.py`.

- Charge soit un modèle TorchScript, soit un `state_dict` ResNet-18.
- Applique une transformation d'image via `ml.transforms.get_transform()`.
- Retourne un couple `(maladie, confiance)`.
- Si la confiance est inférieure au seuil, la sortie devient `Non identifiable`.

#### 3.4.2 Détection de présence par YOLO

Les endpoints `/api/predict` et `/api/realtime/*` utilisent un modèle YOLO pour filtrer les images qui contiennent une plante ou feuille de tomate.

- `contient_plante(image_bytes)` renvoie `True` si au moins une boîte détectée dépasse `SEUIL_CONFIANCE_YOLO`.
- Ce filtre évite les diagnostics sur des photos sans plante.

#### 3.4.3 Pipeline temps réel

- Méthodes : `start_realtime_session`, `process_frame`, `end_realtime_session`, `get_session_status`.
- Une session est créée en mémoire et accumule des observations.
- Les frames sont filtrées par taux d'analyse et qualité GPS avant classification.
- Les images validées sont classifiées, enregistrées, puis regroupées en zones.
- À la fin d'une session, le résumé est construit, des zones sont créées ou mises à jour, et des notifications sont générées.

### 3.5 Architecture de données

#### 3.5.1 Schéma SQL

Le fichier `backend/init_db.sql` définit plusieurs entités.

Principales tables :

- `utilisateur`
  - `id_utilisateur`, `nom`, `email`, `mot_de_passe`, `telephone`, `photo_profil`, `adresse`, `role`
- `maladie`
  - référentiel des maladies, description, symptômes, recommandations, niveau de gravité
- `diagnostic`
  - `id_diagnostic`, `id_utilisateur`, `date_debut`, `date_fin`, `mode_capture`
- `observation`
  - `id_observation`, `id_diagnostic`, `id_maladie`, `timestamp`, `latitude`, `longitude`, `precision_gps`, `image_path`, `confiance`, `maladie_nom`
- `zone_infectee`
  - `id_zone`, `centre_latitude`, `centre_longitude`, `rayon`, `nombre_observations`
- `conversation` / `message`
  - stockage du chatbot historique
- `notification`
  - notifications utilisateur

Le code source utilise également des champs de jointure et des requêtes spatiales PostGIS (`ST_DWithin`, `ST_Contains`, `ST_MakePoint`).

#### 3.5.2 Entités métier

- Diagnostic : session de capture associée à un utilisateur.
- Observation : résultat d'une analyse d'image, avec géolocalisation, confiance et maladie.
- Zone infectée : regroupement d'observations proches (même utilisateur) pour suivre une zone critique.
- Parcelle : champ ou zone de culture associée à l'utilisateur.
- Notification : alerte envoyée à l'utilisateur lors de détections.

### 3.6 Repositories

Le dossier `backend/app/repositories` contient les abstractions SQL :

- `DiagnosticRepository`
- `ObservationRepository`
- `ZoneRepository`
- `MaladieRepository`
- `NotificationRepository`
- `ConversationRepository`

Ces classes centralisent l'accès à la base et simplifient les routes.

### 3.7 Logique métier clé

#### 3.7.1 Regroupement et création de zones

- `RAYON_GROUPEMENT_M` détermine si des observations doivent être regroupées.
- `ZoneRepository.zone_existe_proche` et `trouver_zone_proche_observation` cherchent une zone d'un même utilisateur.
- `ZoneRepository.creer_zone` calcule un rayon dynamique sur la base des observations.
- `ZoneRepository.recalculer_zone` met à jour le centre et le rayon après chaque ajout/suppression d'observation.
- `predict.py` regroupe aussi des observations via une fonction de chaînage (`regrouper_observations`).

#### 3.7.2 Statistiques et agrégation

`backend/app/api/routes/stats.py` produit :

- total de diagnostics
- total de zones
- total de parcelles
- taux d'infection moyen
- répartition des maladies
- top zones et top parcelles

Les calculs excluent les observations `Tomato_healthy`, `Non identifiable` et `Sain` pour les taux de gravité.

#### 3.7.3 Notifications

Le backend génère des notifications lors de la création ou mise à jour de zones infectées.

- Critique : `nombre_observations >= 20`.
- Active : `nombre_observations >= 10`.
- Émergente : sinon.

Les notifications sont enregistrées en base et renvoyées à l'application mobile via `/api/notifications`.

### 3.8 Authentification

- Inscription : `/api/auth/register`
- Connexion : `/api/auth/login`
- Récupération profil : `/api/auth/me`

Le backend utilise JWT signé avec `JWT_SECRET_KEY`.
Les mots de passe sont hachés avec `bcrypt`.

## 4. Mobile

### 4.1 Stack technique

- `Flutter` + Dart
- `image_picker` : capture photo
- `camera` : flux vidéo temps réel
- `geolocator` : géolocalisation GPS
- `dio` : client HTTP
- `sqflite` : stockage local SQLite
- `shared_preferences` : stockage simple des sessions
- `flutter_map` + `latlong2` + `flutter_map_marker_cluster` : cartographie
- `provider` : gestion d'état (présent dans `pubspec.yaml`)
- `fl_chart` : graphiques statistiques

### 4.2 Point d’entrée

- `mobile/lib/main.dart` instancie l'application.
- L'état initial vérifie :
  - affichage d'onboarding
  - authentification
  - rôle (admin / agriculteur)

Routes définies : `/login`, `/home`, `/admin`.

### 4.3 Services mobiles

#### 4.3.1 AuthService

- singleton de gestion du token JWT et des informations utilisateur.
- stocke : `token`, `id_utilisateur`, `nom`, `email`, `role`.
- méthodes : `saveUserData`, `getToken`, `isLoggedIn`, `logout`.

#### 4.3.2 GpsService

- singleton pour suivre la position GPS en continu.
- met en cache la dernière position valide dans `SharedPreferences`.
- utilise `Geolocator.getPositionStream` et un timer de 10 secondes.
- fournit des fallback coordinates si le GPS ne répond pas.
- expose un listener pour les écrans qui ont besoin de position en temps réel.

#### 4.3.3 LocalDatabaseService

- base SQLite locale `tomscan.db`.
- tables : `history`, `conversations`, `messages`.
- stocke l'historique des diagnostics et les conversations chatbot.
- permet la persistance hors connexion pour l'historique.

### 4.4 Écrans principaux

#### 4.4.1 `CameraScreen`

- capture d'image via image picker.
- obtient la localisation GPS haute précision.
- envoie l'image au backend `/api/predict`.
- affiche le résultat dans `ResultScreen`.
- sauvegarde le dernier diagnostic dans `SharedPreferences` et l'historique local.
- propose accès à la carte, notifications, chatbot.

#### 4.4.2 `MapScreen`

- affiche les zones infectées et les diagnostics sur une carte.
- utilise probablement `flutter_map` et `flutter_map_marker_cluster`.
- permet de visualiser les zones par couleur et d’identifier les parcelles.

#### 4.4.3 `RealtimeScanScreen`

- initialise la caméra en haute résolution.
- démarre une session temps réel avec `/api/realtime/start`.
- envoie périodiquement des images à `/api/realtime/{session_id}/frame`.
- affiche le taux de frames analysées, les maladies détectées et les bounding boxes.
- termine la session avec `/api/realtime/{session_id}/end` et affiche un résumé.

#### 4.4.4 `StatsScreen`

- récupère les données via `/api/stats`.
- affiche les synthèses : taux infection, top zones, top parcelles, répartition maladies.

#### 4.4.5 `HistoryScreen`, `NotificationsScreen`, `ChatbotScreen`

- `HistoryScreen` utilise l'historique local pour afficher les diagnostics précédents.
- `NotificationsScreen` lit les notifications backend et probablement marque comme lues.
- `ChatbotScreen` communique avec le backend via `/api/conversations` et `/api/conversations/{id}/messages`.

### 4.5 Configuration mobile

- `mobile/lib/config.dart` définit l'URL backend : `http://192.168.0.176:8000/api`.
- contient également des seuils calés sur le backend : `rayonGroupementM`, `seuilCreationZone`, `fpsCible`, `qualiteImageMin`.

## 5. Scénarios métiers détaillés

### 5.1 Diagnostic photo (capture unique)

1. L'utilisateur prend une photo ou choisit une image.
2. L'application récupère la position GPS.
3. Le frontend envoie : `image`, `latitude`, `longitude`, `precision_gps`, `id_utilisateur` à `/api/predict`.
4. Le backend :
   - sauvegarde l'image en local (`uploads/`).
   - crée un diagnostic `PHOTO`.
   - filtre l'image avec YOLO.
   - si une plante est détectée, appelle ResNet.
   - enregistre une observation.
   - associe la parcelle si le point est dans un polygone de parcelle.
   - regroupe éventuellement des observations en zone infectée.
5. Le backend renvoie le diagnostic, l'identité de la maladie, la confiance et des métadonnées.
6. Le mobile affiche le résultat et sauvegarde localement.

### 5.2 Scan temps réel

1. L'utilisateur démarre le scan temps réel.
2. Le mobile demande une nouvelle session `/api/realtime/start`.
3. La caméra capture des frames à la fréquence cible.
4. Chaque frame est envoyée avec la position GPS à `/api/realtime/{session_id}/frame`.
5. Le backend :
   - filtre les images par YOLO et par confiance ResNet.
   - stocke les observations analysées.
   - garde les zones candidates en mémoire de session.
6. L'utilisateur peut suivre le statut via `/api/realtime/{session_id}/status`.
7. À l'arrêt, `/api/realtime/{session_id}/end` génère un résumé, crée/mets à jour des zones infectées, et crée des notifications.

### 5.3 Parcelles et zones

- Les parcelles sont des entités géospatiales stockées en base.
- Les observations peuvent recevoir un `id_parcelle` si le point est contenu dans le polygone de la parcelle.
- Les zones infectées sont des regroupements d'observations proches.
- Les zones ont un `centre_latitude`, `centre_longitude`, `rayon` et `nombre_observations`.

### 5.4 Statistiques

- `backend/app/api/routes/stats.py` calcule les statistiques pour une période filtrée (`7j`, `30j`, `90j`, `365j`).
- Les métriques incluent : nombre de diagnostics, nombre de zones, nombre de parcelles, taux d'infection, répartition des maladies, top zones et top parcelles.

### 5.5 Chatbot IA

- Le backend `chat.py` utilise `MistralService` pour appeler l'API Mistral.
- Le chatbot est contextualisé sur l'agriculture camerounaise et la tomate.
- Les conversations sont stockées en base via `ConversationRepository`.

## 6. Diagramme d'architecture

```mermaid
flowchart LR
  subgraph Mobile
    A[CameraScreen] -->|POST /predict| B[Backend FastAPI]
    C[RealtimeScanScreen] -->|POST /realtime/start| B
    C -->|POST /realtime/{id}/frame| B
    D[MapScreen] -->|GET /zones| B
    E[StatsScreen] -->|GET /stats| B
    F[Chatbot] -->|POST /conversations| B
  end

  subgraph Backend
    B --> G[IAService ResNet]
    B --> H[YOLO]
    B --> I[PostgreSQL/PostGIS]
    B --> J[Mistral AI]
    B --> K[FileStorage uploads/]
  end

  subgraph Database
    I --> L[utilisateur]
    I --> M[observation]
    I --> N[diagnostic]
    I --> O[zone_infectee]
    I --> P[maladie]
    I --> Q[notification]
  end
```

## 7. Dépendances

### 7.1 Backend (`backend/requirements.txt`)

- fastapi
- uvicorn
- python-multipart
- torch
- torchvision
- pillow
- numpy
- scikit-learn
- psycopg2-binary
- python-jose[cryptography]
- passlib[bcrypt]
- python-dotenv
- mistralai
- pydantic
- pytest
- httpx
- pytest-asyncio

### 7.2 Mobile (`mobile/pubspec.yaml`)

- flutter
- image_picker
- geolocator
- camera
- dio
- flutter_map
- latlong2
- flutter_map_marker_cluster
- permission_handler
- provider
- shared_preferences
- fl_chart
- flutter_markdown
- http
- sqflite
- path_provider
- share_plus

## 8. Fichiers clés

- `backend/app/api/main.py` : configuration FastAPI + inclusion des routers.
- `backend/app/api/routes/predict.py` : diagnostic photo.
- `backend/app/api/routes/realtime.py` : scan temps réel.
- `backend/app/api/routes/stats.py` : calcul des statistiques.
- `backend/app/api/routes/auth.py` : authentification.
- `backend/app/api/routes/chat.py` : chatbot.
- `backend/app/services/ia_service.py` : modèle ResNet et classification.
- `backend/app/services/mistral_service.py` : interface chatbot.
- `backend/app/repositories/zone_repository.py` : logique de zones infectées.
- `backend/init_db.sql` : structure de la base de données.
- `mobile/lib/main.dart` : point d'entrée Flutter.
- `mobile/lib/config.dart` : configuration backend et seuils.
- `mobile/lib/screens/camera_screen.dart` : capture et envoi d'image.
- `mobile/lib/screens/realtime_scan_screen.dart` : scan vidéo temps réel.
- `mobile/lib/services/gps_service.dart` : gestion GPS.
- `mobile/lib/services/auth_service.dart` : gestion de session.
- `mobile/lib/services/local_database_service.dart` : stockage local SQLite.

## 9. Recommandations d’amélioration

- Séparer le code de routage et la logique métier pour améliorer la maintenabilité.
- Ajouter un middleware d'authentification JWT pour sécuriser les endpoints.
- Remplacer l'option `allow_origins: ["*"]` en production.
- Ajouter des tests unitaires et d'intégration sur les routes importantes.
- Standardiser les schémas de réponse JSON dans les routes.
- Consolider les seuils backend/mobile dans un contrat partagé ou une API de configuration.
- Ajouter la gestion des erreurs sur les appels HTTP mobiles.

## 10. Conclusion

TomScan est une application complète qui combine une API ML, des opérations géospatiales, et une application mobile utilisateur final. Le backend réalise un traitement d'image avancé et un regroupement spatial des observations. Le mobile fournit des fonctionnalités terrain efficaces : capture photo, map, scan temps réel et historique local.

Ce document couvre l'architecture existante, les principaux flux et les composants techniques critiques du projet.

# 🍅 TomScan - Diagnostic des maladies de la tomate

[![Dart](https://img.shields.io/badge/Dart-51.5%25-0175C2?style=flat&logo=dart)](https://dart.dev)
[![Python](https://img.shields.io/badge/Python-23.1%25-3776AB?style=flat&logo=python)](https://python.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-22.6%25-4169E1?style=flat&logo=postgresql)](https://postgresql.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Application mobile de diagnostic des maladies de la tomate utilisant l'intelligence artificielle, développée pour les agriculteurs camerounais.

---

## 📱 Fonctionnalités

| Fonctionnalité | Description |
|----------------|-------------|
| 🤖 **Diagnostic IA** | Classification des maladies avec ResNet18 (7 classes) |
| 🎯 **Filtrage YOLO** | Détection des plantes de tomate avant analyse |
| 📍 **Cartographie** | Visualisation des zones infectées sur carte interactive |
| 📊 **Statistiques** | Analyse des données avec export CSV |
| 🎥 **Mode temps réel** | Analyse en direct via la caméra |
| 💬 **Chatbot** | Assistant IA pour les agriculteurs (Mistral) |
| 🔔 **Notifications** | Alertes GPS pour les zones infectées |

---

## 🧠 Modèles IA

| Modèle | Type | Classes | Précision |
|--------|------|---------|-----------|
| **ResNet18** | Classification | 7 | 86.01% |
| **YOLO** | Détection | 1 (tomate) | - |

**Classes ResNet18 :**
- `Tomato_Early_Blight` → Alternariose
- `Tomato_Healthy` → Sain
- `Tomato_leaf_late_blight` → Mildiou
- `Tomato_leaf_yellow_curl_virus` → Virus jaune
- `Tomato_mold_leaf` → Moisissure
- `Tomato_powdery_mildew` → Oïdium
- `Tomato_septoria_leaf_spot` → Septoriose

---

## 🛠️ Installation

### Prérequis

- Python 3.10+
- Flutter 3.29+
- PostgreSQL 14+ avec PostGIS

### Backend

```bash
# 1. Cloner le projet
git clone https://github.com/Tuekam/tomScan.git
cd tomScan/backend

# 2. Créer l'environnement virtuel
python -m venv venv
source venv/bin/activate  # Linux/Mac
# ou
venv\Scripts\activate     # Windows

# 3. Installer les dépendances
pip install -r requirements.txt

# 4. Configurer les variables d'environnement
cp .env.example .env
# Modifier .env avec vos paramètres

# 5. Lancer le serveur
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
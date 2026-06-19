# backend/app/core/config.py
import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    # Base de données
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/tomscan")
    
    # Modèles IA
    MODEL_PATH: str = os.getenv("MODEL_PATH", "ml/best_resnet18_augmented.pth")
    YOLO_MODEL_PATH: str = os.getenv("YOLO_MODEL_PATH", "ml/yolo_plante_tomate.pt")
    
    # Seuils IA
    SEUIL_CONFIANCE_YOLO: float = float(os.getenv("SEUIL_CONFIANCE_YOLO", "0.8"))
    SEUIL_CONFIANCE_RESNET: float = float(os.getenv("SEUIL_CONFIANCE_RESNET", "0.5"))
    
    # Règles métier
    RAYON_GROUPEMENT_M: float = float(os.getenv("RAYON_GROUPEMENT_M", "1.0"))
    SEUIL_CREATION_ZONE: int = int(os.getenv("SEUIL_CREATION_ZONE", "10"))
    RAYON_RECHERCHE_ZONE: float = float(os.getenv("RAYON_RECHERCHE_ZONE", "1.0"))
    
    # Mode temps réel
    RAYON_DEDOUBLONNAGE_GPS_PRECIS: float = float(os.getenv("RAYON_DEDOUBLONNAGE_GPS_PRECIS", "0.5"))
    RAYON_DEDOUBLONNAGE_GPS_MOYEN: float = float(os.getenv("RAYON_DEDOUBLONNAGE_GPS_MOYEN", "2.0"))
    RAYON_DEDOUBLONNAGE_GPS_IMPRECIS: float = float(os.getenv("RAYON_DEDOUBLONNAGE_GPS_IMPRECIS", "5.0"))
    RAYON_DEDOUBLONNAGE_GPS_TRES_IMPRECIS: float = float(os.getenv("RAYON_DEDOUBLONNAGE_GPS_TRES_IMPRECIS", "10.0"))
    
    # FPS et qualité
    FPS_CIBLE: int = int(os.getenv("FPS_CIBLE", "4"))
    QUALITE_IMAGE_MIN: float = float(os.getenv("QUALITE_IMAGE_MIN", "20.0"))
    
    # Timeout session
    TIMEOUT_SESSION_SECONDS: int = int(os.getenv("TIMEOUT_SESSION_SECONDS", "900"))
    
    # Chatbot
    MISTRAL_API_KEY: str = os.getenv("MISTRAL_API_KEY", "")
    
    # Upload
    UPLOAD_DIR: str = os.getenv("UPLOAD_DIR", "uploads")
    
    # ============================================================
    # AJOUT : JWT pour l'authentification
    # ============================================================
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "tomscan_secret_key_2026_change_this_in_production")
    JWT_ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256")
    JWT_EXPIRATION_DAYS: int = int(os.getenv("JWT_EXPIRATION_DAYS", "7"))

settings = Settings()
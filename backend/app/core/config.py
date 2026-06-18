from dotenv import load_dotenv
import os

load_dotenv()

class Settings:
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/tomscan")
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "secret")
    MISTRAL_API_KEY: str = os.getenv("MISTRAL_API_KEY", "")
    MODEL_PATH: str = os.getenv("MODEL_PATH", "ml/best_resnet18_augmented.pth")

settings = Settings()
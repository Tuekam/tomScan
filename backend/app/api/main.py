# backend/app/api/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes import predict
from app.api.routes import zones
from app.api.routes import notifications
from app.api.routes import parcelles
from app.api.routes import diagnostics
from app.api.routes import maladies
from app.api.routes import images
from app.api.routes import chat
from app.api.routes import stats
from app.api.routes import observations
from app.api.routes import realtime
from app.api.routes import sessions
from app.api.routes import history
from app.api.routes import utilisateur
from app.api.routes import auth
from app.api.routes import admin

app = FastAPI(title="TomScan API", version="1.0.0")

# ============================================================
# 🔥 CONFIGURATION CORS (autoriser les requêtes du navigateur)
# ============================================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8000",
        "http://localhost:8080",
        "http://127.0.0.1:8000",
        "http://127.0.0.1:8080",
        "http://192.168.0.176:8000",  # Ton IP locale
        "http://192.168.0.176:8080",
        "*",  # Pour le développement (à retirer en production)
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Routes
app.include_router(predict.router, prefix="/api", tags=["prediction"])
app.include_router(zones.router, prefix="/api", tags=["zones"])
app.include_router(notifications.router, prefix="/api", tags=["notifications"])
app.include_router(parcelles.router, prefix="/api", tags=["parcelles"])
app.include_router(diagnostics.router, prefix="/api", tags=["diagnostics"])
app.include_router(maladies.router, prefix="/api", tags=["maladies"])
app.include_router(images.router, prefix="/api", tags=["images"])
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(stats.router, prefix="/api", tags=["stats"])
app.include_router(observations.router, prefix="/api", tags=["observations"])
app.include_router(realtime.router, prefix="/api", tags=["realtime"])
app.include_router(sessions.router, prefix="/api", tags=["sessions"])
app.include_router(history.router, prefix="/api", tags=["history"])
app.include_router(utilisateur.router, prefix="/api", tags=["utilisateur"])
app.include_router(auth.router, prefix="/api", tags=["auth"])
app.include_router(admin.router, prefix="/api", tags=["admin"])

@app.get("/")
def root():
    return {"message": "TomScan API is running"}
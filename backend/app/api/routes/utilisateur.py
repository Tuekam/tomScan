# backend/app/api/routes/utilisateur.py
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
import os
import uuid
import asyncpg
from app.core.config import settings

router = APIRouter()

UPLOAD_DIR = "uploads/profils"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@router.get("/utilisateur/{user_id}")
async def get_utilisateur(user_id: int = 1):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        row = await conn.fetchrow("""
            SELECT id_utilisateur, nom, email, telephone, photo_profil, date_inscription, adresse, role
            FROM utilisateur
            WHERE id_utilisateur = $1
        """, user_id)
        
        if not row:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        return {
            "id_utilisateur": row["id_utilisateur"],
            "nom": row["nom"],
            "email": row["email"],
            "telephone": row["telephone"],
            "photo_profil": row["photo_profil"],
            "date_inscription": row["date_inscription"].isoformat() if row["date_inscription"] else None,
            "adresse": row["adresse"],
            "role": row["role"]
        }
    finally:
        await conn.close()

@router.post("/utilisateur/{user_id}/photo")
async def upload_photo_profil(
    user_id: int,
    image: UploadFile = File(...)
):
    """Upload la photo de profil de l'utilisateur"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Vérifier que l'utilisateur existe
        user = await conn.fetchrow("SELECT id_utilisateur FROM utilisateur WHERE id_utilisateur = $1", user_id)
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        # Sauvegarder l'image
        extension = image.filename.split('.')[-1] if '.' in image.filename else 'jpg'
        filename = f"profile_{user_id}.{extension}"
        filepath = os.path.join(UPLOAD_DIR, filename)
        
        content = await image.read()
        with open(filepath, "wb") as f:
            f.write(content)
        
        # Mettre à jour la base de données
        photo_url = f"/api/images/profils/{filename}"
        await conn.execute("""
            UPDATE utilisateur
            SET photo_profil = $1
            WHERE id_utilisateur = $2
        """, photo_url, user_id)
        
        return {"status": "ok", "photo_url": photo_url}
    finally:
        await conn.close()
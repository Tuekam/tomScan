# backend/app/api/routes/auth.py
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, EmailStr
import asyncpg
import bcrypt
import jwt
from datetime import datetime, timedelta
from app.core.config import settings

router = APIRouter()

# Modèles Pydantic
class RegisterRequest(BaseModel):
    nom: str
    email: EmailStr
    mot_de_passe: str
    telephone: str = ""
    adresse: str = ""
    role: str = "agriculteur"

class LoginRequest(BaseModel):
    email: EmailStr
    mot_de_passe: str

class LoginResponse(BaseModel):
    id_utilisateur: int
    nom: str
    email: str
    role: str
    token: str
    photo_profil: str | None

# Fonctions utilitaires
def hash_password(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))

def create_token(user_id: int, email: str) -> str:
    payload = {
        "id_utilisateur": user_id,
        "email": email,
        "exp": datetime.utcnow() + timedelta(days=7)
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm="HS256")

@router.post("/auth/register")
async def register(data: RegisterRequest):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Vérifier si l'email existe déjà
        existing = await conn.fetchrow(
            "SELECT id_utilisateur FROM utilisateur WHERE email = $1",
            data.email
        )
        if existing:
            raise HTTPException(status_code=400, detail="Cet email est déjà utilisé")

        # Hacher le mot de passe
        hashed_password = hash_password(data.mot_de_passe)

        # Insérer l'utilisateur
        row = await conn.fetchrow("""
            INSERT INTO utilisateur (nom, email, mot_de_passe, telephone, adresse, role, date_inscription)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            RETURNING id_utilisateur, nom, email, role, photo_profil
        """, data.nom, data.email, hashed_password, data.telephone, data.adresse, data.role)

        # Créer le token
        token = create_token(row["id_utilisateur"], row["email"])

        return {
            "id_utilisateur": row["id_utilisateur"],
            "nom": row["nom"],
            "email": row["email"],
            "role": row["role"],
            "photo_profil": row["photo_profil"],
            "token": token
        }
    finally:
        await conn.close()

@router.post("/auth/login")
async def login(data: LoginRequest):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Récupérer l'utilisateur
        row = await conn.fetchrow("""
            SELECT id_utilisateur, nom, email, mot_de_passe, role, photo_profil
            FROM utilisateur
            WHERE email = $1
        """, data.email)

        if not row:
            raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect")

        # Vérifier le mot de passe
        if not verify_password(data.mot_de_passe, row["mot_de_passe"]):
            raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect")

        # Créer le token
        token = create_token(row["id_utilisateur"], row["email"])

        return {
            "id_utilisateur": row["id_utilisateur"],
            "nom": row["nom"],
            "email": row["email"],
            "role": row["role"],
            "photo_profil": row["photo_profil"],
            "token": token
        }
    finally:
        await conn.close()

@router.get("/auth/me")
async def get_current_user(token: str):
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=["HS256"])
        user_id = payload.get("id_utilisateur")
        if not user_id:
            raise HTTPException(status_code=401, detail="Token invalide")

        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT id_utilisateur, nom, email, role, photo_profil
                FROM utilisateur
                WHERE id_utilisateur = $1
            """, user_id)
            if not row:
                raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
            return {
                "id_utilisateur": row["id_utilisateur"],
                "nom": row["nom"],
                "email": row["email"],
                "role": row["role"],
                "photo_profil": row["photo_profil"]
            }
        finally:
            await conn.close()
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Token invalide")
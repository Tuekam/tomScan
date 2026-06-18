from fastapi import APIRouter
import asyncpg
from app.core.config import settings

router = APIRouter()

@router.get("/maladies")
async def get_maladies():
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        rows = await conn.fetch("SELECT id_maladie, nom FROM maladie ORDER BY nom")
        return [{"id": r["id_maladie"], "nom": r["nom"]} for r in rows]
    finally:
        await conn.close()
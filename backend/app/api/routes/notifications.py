from fastapi import APIRouter, Depends
import asyncpg
from app.core.config import settings

router = APIRouter()

@router.get("/notifications")
async def get_notifications(id_utilisateur: int = 1):  # À remplacer par l'utilisateur connecté
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        rows = await conn.fetch("""
            SELECT id_notification, titre, message, date_creation, lu, type
            FROM notification
            WHERE id_utilisateur = $1 AND lu = FALSE
            ORDER BY date_creation DESC
        """, id_utilisateur)
        return [dict(row) for row in rows]
    finally:
        await conn.close()

@router.post("/notifications/{id}/read")
async def mark_notification_read(id: int):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        await conn.execute("UPDATE notification SET lu = TRUE WHERE id_notification = $1", id)
        return {"status": "ok", "id": id}
    finally:
        await conn.close()
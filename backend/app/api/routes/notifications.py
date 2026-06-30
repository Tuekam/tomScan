# backend/app/api/routes/notifications.py
from fastapi import APIRouter, HTTPException
import asyncpg
from app.core.config import settings

router = APIRouter()

@router.get("/notifications")
async def get_notifications(user_id: int = 1):
    """Récupère toutes les notifications d'un utilisateur"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        rows = await conn.fetch("""
            SELECT 
                n.id_notification,
                n.titre,
                n.message,
                n.date_creation,
                n.lu,
                n.type,
                n.id_zone,
                n.id_parcelle,
                z.centre_latitude as latitude,
                z.centre_longitude as longitude
            FROM notification n
            LEFT JOIN zone_infectee z ON n.id_zone = z.id_zone
            WHERE n.id_utilisateur = $1
            ORDER BY n.date_creation DESC
        """, user_id)
        
        result = []
        for row in rows:
            result.append({
                "id_notification": row["id_notification"],
                "titre": row["titre"],
                "message": row["message"],
                "date_creation": row["date_creation"].isoformat() if row["date_creation"] else None,
                "lu": row["lu"],
                "type": row["type"],
                "id_zone": row["id_zone"],
                "id_parcelle": row["id_parcelle"],
                "latitude": float(row["latitude"]) if row["latitude"] else None,
                "longitude": float(row["longitude"]) if row["longitude"] else None
            })
        return result
    finally:
        await conn.close()

@router.post("/notifications/{id}/read")
async def mark_notification_read(id: int):
    """Marque une notification comme lue"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        result = await conn.execute(
            "UPDATE notification SET lu = TRUE WHERE id_notification = $1",
            id
        )
        if int(result.split()[-1]) == 0:
            raise HTTPException(status_code=404, detail="Notification non trouvée")
        return {"status": "ok", "id": id}
    finally:
        await conn.close()

@router.post("/notifications/read-all")
async def mark_all_notifications_read(user_id: int = 1):
    """Marque toutes les notifications d'un utilisateur comme lues"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        await conn.execute(
            "UPDATE notification SET lu = TRUE WHERE id_utilisateur = $1 AND lu = FALSE",
            user_id
        )
        return {"status": "ok", "message": "Toutes les notifications ont été marquées comme lues"}
    finally:
        await conn.close()


@router.get("/notifications/unread/count")
async def get_unread_count(user_id: int = 1):
    """Récupère le nombre de notifications non lues"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        count = await conn.fetchval("""
            SELECT COUNT(*) 
            FROM notification 
            WHERE id_utilisateur = $1 AND lu = FALSE
        """, user_id)
        return {"count": count or 0}
    finally:
        await conn.close()
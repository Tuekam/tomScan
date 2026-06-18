import asyncpg
from app.core.config import settings

class NotificationRepository:
    async def create_notification(self, id_utilisateur, titre, message, type_notif):
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            await conn.execute("""
                INSERT INTO notification (id_utilisateur, titre, message, type)
                VALUES ($1, $2, $3, $4)
            """, id_utilisateur, titre, message, type_notif)
        finally:
            await conn.close()
    
    async def get_non_lues(self, id_utilisateur):
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch("""
                SELECT id_notification, titre, message, date_creation, type
                FROM notification
                WHERE id_utilisateur = $1 AND lu = FALSE
                ORDER BY date_creation DESC
            """, id_utilisateur)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
    
    async def marquer_comme_lue(self, id_notification):
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            await conn.execute("UPDATE notification SET lu = TRUE WHERE id_notification = $1", id_notification)
        finally:
            await conn.close()
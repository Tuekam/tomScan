import asyncpg
from app.core.config import settings

class ConversationRepository:
    async def create_conversation(self, user_id: int, sujet: str = None) -> int:
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow(
                "INSERT INTO conversation (id_utilisateur, sujet) VALUES ($1, $2) RETURNING id_conversation",
                user_id, sujet or "Nouvelle conversation"
            )
            return row["id_conversation"]
        finally:
            await conn.close()

    async def get_conversations_by_user(self, user_id: int):
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch(
                "SELECT id_conversation, sujet, date_creation FROM conversation WHERE id_utilisateur = $1 ORDER BY date_creation DESC",
                user_id
            )
            return [dict(r) for r in rows]
        finally:
            await conn.close()

    async def get_messages(self, conversation_id: int):
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch(
                "SELECT id_message, question, reponse, date_message FROM message WHERE id_conversation = $1 ORDER BY date_message",
                conversation_id
            )
            return [dict(r) for r in rows]
        finally:
            await conn.close()

    async def add_message(self, conversation_id: int, question: str, reponse: str):
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            await conn.execute(
                "INSERT INTO message (id_conversation, question, reponse) VALUES ($1, $2, $3)",
                conversation_id, question, reponse
            )
        finally:
            await conn.close()
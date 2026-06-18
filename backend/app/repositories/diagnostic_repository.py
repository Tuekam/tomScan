# backend/app/repositories/diagnostic_repository.py
import asyncpg
from app.core.config import settings

class DiagnosticRepository:
    async def save_diagnostic(self, id_utilisateur: int, mode_capture: str, id_parcelle: int = None):
        print(f"💾 Sauvegarde diagnostic : utilisateur={id_utilisateur}, mode={mode_capture}, parcelle={id_parcelle}")
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                INSERT INTO diagnostic (id_utilisateur, date_debut, mode_capture, id_parcelle)
                VALUES ($1, NOW(), $2, $3)
                RETURNING id_diagnostic
            """, id_utilisateur, mode_capture, id_parcelle)
            return row["id_diagnostic"]
        finally:
            await conn.close()
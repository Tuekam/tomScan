# backend/app/repositories/diagnostic_repository.py
import asyncpg
from app.core.config import settings

class DiagnosticRepository:
    
    async def save_diagnostic(self, id_utilisateur: int, mode: str, id_parcelle: int = None) -> int:
        """Sauvegarde un diagnostic"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                INSERT INTO diagnostic (id_utilisateur, date_debut, mode_capture, id_parcelle)
                VALUES ($1, NOW(), $2, $3)
                RETURNING id_diagnostic
            """, id_utilisateur, mode, id_parcelle)
            return row['id_diagnostic']
        finally:
            await conn.close()
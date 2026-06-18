# backend/app/repositories/maladie_repository.py
import asyncpg
from app.core.config import settings

class MaladieRepository:

    async def get_id_by_nom(self, nom: str) -> int | None:
        """Retourne l'ID d'une maladie en ignorant la casse."""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            # ILIKE = case-insensitive
            row = await conn.fetchrow(
                "SELECT id_maladie FROM maladie WHERE nom ILIKE $1",
                nom
            )
            return row["id_maladie"] if row else None
        finally:
            await conn.close()

    async def get_details_by_id(self, id_maladie: int) -> dict | None:
        """Récupère les détails complets d'une maladie."""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT 
                    id_maladie,
                    nom,
                    description, 
                    symptomes, 
                    recommandation, 
                    niveau_gravite, 
                    image_reference
                FROM maladie 
                WHERE id_maladie = $1
            """, id_maladie)
            return dict(row) if row else None
        finally:
            await conn.close()

    async def get_all_maladies(self) -> list[dict]:
        """Récupère toutes les maladies."""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch("""
                SELECT 
                    id_maladie,
                    nom,
                    description, 
                    symptomes, 
                    recommandation, 
                    niveau_gravite, 
                    image_reference
                FROM maladie 
                ORDER BY id_maladie
            """)
            return [dict(row) for row in rows]
        finally:
            await conn.close()
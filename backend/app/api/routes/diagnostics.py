# backend/app/api/routes/diagnostics.py
from fastapi import APIRouter, HTTPException, Query
from datetime import datetime
import asyncpg
from app.core.config import settings

router = APIRouter()

@router.get("/diagnostics")
async def get_diagnostics(
    user_id: int = Query(1, description="ID de l'utilisateur"),
    maladie: str | None = Query(None, description="Filtrer par maladie"),
    parcelle_id: int | None = Query(None, description="Filtrer par parcelle"),
    date_debut: str | None = Query(None, description="Date début (YYYY-MM-DD)"),
    date_fin: str | None = Query(None, description="Date fin (YYYY-MM-DD)")
):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        query = """
            SELECT 
                d.id_diagnostic,
                d.date_debut,
                d.mode_capture,
                o.id_observation,
                o.latitude,
                o.longitude,
                o.maladie_nom,
                o.confiance,
                o.timestamp,
                o.image_path,
                p.id_parcelle,
                p.nom as parcelle_nom,
                m.description,
                m.symptomes,
                m.recommandation,
                m.niveau_gravite
            FROM diagnostic d
            LEFT JOIN observation o ON d.id_diagnostic = o.id_diagnostic
            LEFT JOIN parcelle p ON o.id_parcelle = p.id_parcelle
            LEFT JOIN maladie m ON o.id_maladie = m.id_maladie
            WHERE d.id_utilisateur = $1
        """
        params = [user_id]
        param_index = 2

        if maladie:
            query += f" AND o.maladie_nom ILIKE ${param_index}"
            params.append(f"%{maladie}%")
            param_index += 1

        if parcelle_id:
            query += f" AND o.id_parcelle = ${param_index}"
            params.append(parcelle_id)
            param_index += 1

        if date_debut:
            query += f" AND d.date_debut >= ${param_index}::timestamp"
            params.append(date_debut)
            param_index += 1

        if date_fin:
            query += f" AND d.date_debut <= ${param_index}::timestamp"
            params.append(date_fin)
            param_index += 1

        query += " ORDER BY d.date_debut DESC"

        rows = await conn.fetch(query, *params)

        result = []
        for row in rows:
            result.append({
                "id_diagnostic": row["id_diagnostic"],
                "id_observation": row["id_observation"],
                "date_debut": row["date_debut"].isoformat() if row["date_debut"] else None,
                "mode_capture": row["mode_capture"],
                "maladie_nom": row["maladie_nom"],
                "confiance": float(row["confiance"]) if row["confiance"] else None,
                "latitude": float(row["latitude"]) if row["latitude"] else None,
                "longitude": float(row["longitude"]) if row["longitude"] else None,
                "timestamp": row["timestamp"].isoformat() if row["timestamp"] else None,
                "image_path": row["image_path"],
                "parcelle_id": row["id_parcelle"],
                "parcelle_nom": row["parcelle_nom"],
                "description": row["description"],
                "symptomes": row["symptomes"],
                "recommandation": row["recommandation"],
                "niveau_gravite": row["niveau_gravite"]
            })
        return result
    finally:
        await conn.close()


@router.delete("/diagnostics/{id_diagnostic}")
async def delete_diagnostic(id_diagnostic: int):
    """Supprime un diagnostic et ses observations associées"""
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Supprimer les observations liées
        await conn.execute("DELETE FROM observation WHERE id_diagnostic = $1", id_diagnostic)
        # Supprimer le diagnostic
        result = await conn.execute("DELETE FROM diagnostic WHERE id_diagnostic = $1", id_diagnostic)
        if int(result.split()[-1]) == 0:
            raise HTTPException(status_code=404, detail="Diagnostic non trouvé")
        return {"status": "ok", "message": "Diagnostic supprimé"}
    finally:
        await conn.close()
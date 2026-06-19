# backend/app/api/routes/sessions.py
from fastapi import APIRouter, HTTPException, Query, Form
import asyncpg
import json
from app.core.config import settings

router = APIRouter()

@router.get("/sessions")
async def get_sessions(
    user_id: int = Query(1),
    limit: int = Query(50),
    offset: int = Query(0)
):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        rows = await conn.fetch("""
            SELECT 
                id_session,
                date_debut,
                date_fin,
                mode,
                total_frames,
                frames_analysees,
                zones_crees,
                resume,
                EXTRACT(EPOCH FROM (date_fin - date_debut)) as duree_secondes
            FROM session
            WHERE id_utilisateur = $1
            ORDER BY date_debut DESC
            LIMIT $2 OFFSET $3
        """, user_id, limit, offset)
        
        result = []
        for row in rows:
            item = {
                "id_session": row["id_session"],
                "date_debut": row["date_debut"].isoformat() if row["date_debut"] else None,
                "date_fin": row["date_fin"].isoformat() if row["date_fin"] else None,
                "mode": row["mode"],
                "total_frames": row["total_frames"],
                "frames_analysees": row["frames_analysees"],
                "zones_crees": row["zones_crees"],
                "duree_secondes": round(row["duree_secondes"] or 0, 1)
            }
            if row["resume"]:
                if isinstance(row["resume"], str):
                    item["resume"] = json.loads(row["resume"])
                else:
                    item["resume"] = row["resume"]
            result.append(item)
        return result
    finally:
        await conn.close()


@router.get("/sessions/{id_session}")
async def get_session_detail(id_session: int):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        row = await conn.fetchrow("""
            SELECT 
                id_session,
                id_utilisateur,
                date_debut,
                date_fin,
                mode,
                total_frames,
                frames_analysees,
                zones_crees,
                resume,
                EXTRACT(EPOCH FROM (date_fin - date_debut)) as duree_secondes
            FROM session
            WHERE id_session = $1
        """, id_session)
        
        if not row:
            raise HTTPException(status_code=404, detail="Session non trouvée")
        
        resume_data = {}
        if row["resume"]:
            if isinstance(row["resume"], str):
                resume_data = json.loads(row["resume"])
            else:
                resume_data = row["resume"]
        
        return {
            "id_session": row["id_session"],
            "id_utilisateur": row["id_utilisateur"],
            "date_debut": row["date_debut"].isoformat() if row["date_debut"] else None,
            "date_fin": row["date_fin"].isoformat() if row["date_fin"] else None,
            "mode": row["mode"],
            "total_frames": row["total_frames"],
            "frames_analysees": row["frames_analysees"],
            "zones_crees": row["zones_crees"],
            "duree_secondes": round(row["duree_secondes"] or 0, 1),
            "resume": resume_data
        }
    finally:
        await conn.close()


@router.delete("/sessions/{id_session}")
async def delete_session(
    id_session: int,
    user_id: int = Form(1)  # ← AJOUTER
):
    """
    Supprime une session après vérification que l'utilisateur en est le propriétaire
    """
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Vérifier que la session appartient à l'utilisateur
        row = await conn.fetchrow(
            "SELECT id_session FROM session WHERE id_session = $1 AND id_utilisateur = $2",
            id_session, user_id
        )
        if not row:
            raise HTTPException(status_code=403, detail="Accès non autorisé à cette session")
        
        result = await conn.execute("DELETE FROM session WHERE id_session = $1", id_session)
        if int(result.split()[-1]) == 0:
            raise HTTPException(status_code=404, detail="Session non trouvée")
        return {"status": "ok", "message": "Session supprimée"}
    finally:
        await conn.close()
# backend/app/api/routes/observations.py
from fastapi import APIRouter, HTTPException, Form
import asyncpg
from app.repositories.observation_repository import ObservationRepository
from app.repositories.zone_repository import ZoneRepository
from app.core.config import settings

router = APIRouter()
obs_repo = ObservationRepository()
zone_repo = ZoneRepository()

@router.delete("/observations/{id_observation}")
async def delete_observation(
    id_observation: int,
    user_id: int = Form(1)  # ← AJOUTER
):
    """
    Supprime une observation après vérification que l'utilisateur en est le propriétaire
    """
    # 1. Vérifier que l'observation appartient à l'utilisateur
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        row = await conn.fetchrow("""
            SELECT o.id_observation, o.id_diagnostic
            FROM observation o
            JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
            WHERE o.id_observation = $1 AND d.id_utilisateur = $2
        """, id_observation, user_id)
        
        if not row:
            raise HTTPException(status_code=403, detail="Accès non autorisé à cette observation")
    finally:
        await conn.close()
    
    # 2. Trouver la zone associée
    zone_id = await obs_repo.trouver_zone_associee(id_observation)
    
    # 3. Supprimer l'observation
    success = await obs_repo.delete_observation(id_observation)
    if not success:
        raise HTTPException(status_code=404, detail="Observation non trouvée")
    
    # 4. Recalculer la zone si nécessaire
    if zone_id:
        await zone_repo.recalculer_zone_apres_suppression(zone_id)
    
    return {"status": "ok", "message": "Observation supprimée"}
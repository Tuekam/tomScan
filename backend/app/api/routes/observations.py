# backend/app/api/routes/observations.py
from fastapi import APIRouter, HTTPException
from app.repositories.observation_repository import ObservationRepository
from app.repositories.zone_repository import ZoneRepository

router = APIRouter()
obs_repo = ObservationRepository()
zone_repo = ZoneRepository()

@router.delete("/observations/{id_observation}")
async def delete_observation(id_observation: int):
    # 1. Trouver la zone associée
    zone_id = await obs_repo.trouver_zone_associee(id_observation)
    
    # 2. Supprimer l'observation
    success = await obs_repo.delete_observation(id_observation)
    if not success:
        raise HTTPException(status_code=404, detail="Observation non trouvée")
    
    # 3. Recalculer la zone si nécessaire
    if zone_id:
        await zone_repo.recalculer_zone_apres_suppression(zone_id)
    
    return {"status": "ok", "message": "Observation supprimée"}
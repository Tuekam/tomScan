# backend/app/api/routes/parcelles.py
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Tuple
from app.repositories.parcelle_repository import ParcelleRepository

router = APIRouter()

class ParcelleCreate(BaseModel):
    nom: str
    points: List[Tuple[float, float]]  # (latitude, longitude)
    id_utilisateur: int = 1

@router.post("/parcelles")
async def create_parcelle(parcelle: ParcelleCreate):
    repo = ParcelleRepository()
    # Vérifier chevauchement
    if await repo.verifier_chevauchement(parcelle.id_utilisateur, parcelle.points):
        raise HTTPException(status_code=400, detail="La parcelle chevauche une parcelle existante")
    id_parcelle = await repo.creer_parcelle(parcelle.id_utilisateur, parcelle.nom, parcelle.points)
    return {"status": "ok", "message": "Parcelle créée", "id": id_parcelle}

@router.get("/parcelles")
async def get_parcelles(id_utilisateur: int = 1):
    repo = ParcelleRepository()
    return await repo.get_parcelles(id_utilisateur)

@router.get("/parcelles/{id}")
async def get_parcelle(id: int):
    repo = ParcelleRepository()
    parcelle = await repo.get_parcelle_by_id(id)
    if not parcelle:
        raise HTTPException(status_code=404, detail="Parcelle non trouvée")
    return parcelle

@router.get("/parcelles/{id}/stats")
async def get_parcelle_stats(id: int):
    repo = ParcelleRepository()
    return await repo.calculer_taux_infection(id)

@router.delete("/parcelles/{id_parcelle}")
async def delete_parcelle(id_parcelle: int):
    repo = ParcelleRepository()
    success = await repo.supprimer_parcelle(id_parcelle)
    if not success:
        raise HTTPException(status_code=404, detail="Parcelle non trouvée")
    return {"status": "ok", "message": "Parcelle supprimée"}
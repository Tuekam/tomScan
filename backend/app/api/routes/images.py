# backend/app/api/routes/images.py
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
import os
from app.core.config import settings

router = APIRouter()

@router.get("/images/{filename}")
async def get_image(filename: str):
    file_path = os.path.join(settings.UPLOAD_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Image not found")
    return FileResponse(file_path)
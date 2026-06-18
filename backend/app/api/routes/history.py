# backend/app/api/routes/history.py
from fastapi import APIRouter, Query
import asyncpg
import json
from app.core.config import settings

router = APIRouter()

@router.get("/history")
async def get_history(
    user_id: int = Query(1),
    limit: int = Query(50),
    offset: int = Query(0),
    type: str | None = Query(None, description="photo, realtime, ou tous"),
    maladie: str | None = Query(None),
    date_debut: str | None = Query(None),
    date_fin: str | None = Query(None)
):
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        items = []
        
        # === 1. DIAGNOSTICS PHOTO ===
        if type is None or type == "photo":
            photo_query = """
                SELECT 
                    d.id_diagnostic as id,
                    d.date_debut as date,
                    'photo' as type,
                    o.id_observation,
                    o.maladie_nom,
                    o.confiance,
                    o.latitude,
                    o.longitude,
                    p.nom as parcelle_nom,
                    o.image_path,
                    m.description,
                    m.symptomes,
                    m.recommandation,
                    m.niveau_gravite
                FROM diagnostic d
                JOIN observation o ON d.id_diagnostic = o.id_diagnostic
                LEFT JOIN parcelle p ON o.id_parcelle = p.id_parcelle
                LEFT JOIN maladie m ON o.id_maladie = m.id_maladie
                WHERE d.id_utilisateur = $1
                  AND d.mode_capture = 'PHOTO'
            """
            params = [user_id]
            param_index = 2
            
            if maladie:
                photo_query += f" AND o.maladie_nom ILIKE ${param_index}"
                params.append(f"%{maladie}%")
                param_index += 1
            if date_debut:
                photo_query += f" AND d.date_debut >= ${param_index}::date"
                params.append(date_debut)
                param_index += 1
            if date_fin:
                photo_query += f" AND d.date_debut <= ${param_index}::date"
                params.append(date_fin)
                param_index += 1
            
            photo_query += f" ORDER BY d.date_debut DESC LIMIT {limit} OFFSET {offset}"
            
            photo_rows = await conn.fetch(photo_query, *params)
            
            for row in photo_rows:
                items.append({
                    "id": row["id"],
                    "id_observation": row["id_observation"],
                    "date": row["date"].isoformat() if row["date"] else None,
                    "type": "photo",
                    "maladie_nom": row["maladie_nom"],
                    "confiance": float(row["confiance"]) if row["confiance"] else None,
                    "latitude": float(row["latitude"]) if row["latitude"] else None,
                    "longitude": float(row["longitude"]) if row["longitude"] else None,
                    "parcelle_nom": row["parcelle_nom"],
                    "image_path": row["image_path"],
                    "description": row["description"],
                    "symptomes": row["symptomes"],
                    "recommandation": row["recommandation"],
                    "niveau_gravite": row["niveau_gravite"]
                })
        
        # === 2. SESSIONS TEMPS RÉEL ===
        if type is None or type == "realtime":
            realtime_query = """
                SELECT 
                    id_session as id,
                    date_debut as date,
                    'realtime' as type,
                    total_frames,
                    frames_analysees,
                    zones_crees,
                    resume,
                    EXTRACT(EPOCH FROM (date_fin - date_debut)) as duree_secondes
                FROM session
                WHERE id_utilisateur = $1
            """
            params2 = [user_id]
            param_index2 = 2
            
            if maladie:
                realtime_query += f" AND resume::text ILIKE ${param_index2}"
                params2.append(f"%{maladie}%")
                param_index2 += 1
            if date_debut:
                realtime_query += f" AND date_debut >= ${param_index2}::date"
                params2.append(date_debut)
                param_index2 += 1
            if date_fin:
                realtime_query += f" AND date_debut <= ${param_index2}::date"
                params2.append(date_fin)
                param_index2 += 1
            
            realtime_query += f" ORDER BY date_debut DESC LIMIT {limit} OFFSET {offset}"
            
            session_rows = await conn.fetch(realtime_query, *params2)
            
            for row in session_rows:
                resume_data = {}
                if row["resume"]:
                    try:
                        if isinstance(row["resume"], str):
                            resume_data = json.loads(row["resume"])
                        else:
                            resume_data = row["resume"]
                    except:
                        resume_data = {}
                
                items.append({
                    "id": row["id"],
                    "date": row["date"].isoformat() if row["date"] else None,
                    "type": "realtime",
                    "total_frames": row["total_frames"],
                    "frames_analysees": row["frames_analysees"],
                    "zones_crees": row["zones_crees"],
                    "duree_secondes": round(row["duree_secondes"] or 0, 1),
                    "maladies_stats": resume_data.get("maladies_stats", {}),
                    "total_observations": resume_data.get("total_observations", 0),
                    "resume": resume_data,
                })
        
        items.sort(key=lambda x: x.get("date", ""), reverse=True)
        
        return {
            "items": items,
            "total": len(items),
            "limit": limit,
            "offset": offset
        }
    except Exception as e:
        print(f"Erreur dans /history: {e}")
        raise
    finally:
        await conn.close()
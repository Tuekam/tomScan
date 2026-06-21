# backend/app/api/routes/admin.py
from fastapi import APIRouter, HTTPException, Depends, Query
import asyncpg
import jwt
from app.core.config import settings
from app.repositories.zone_repository import ZoneRepository
from app.repositories.parcelle_repository import ParcelleRepository
from app.repositories.diagnostic_repository import DiagnosticRepository

router = APIRouter()
zone_repo = ZoneRepository()
parcelle_repo = ParcelleRepository()
diag_repo = DiagnosticRepository()

# Middleware simple pour vérifier le token admin
async def verifier_admin(token: str):
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=["HS256"])
        user_id = payload.get("id_utilisateur")
        if not user_id:
            raise HTTPException(status_code=401, detail="Token invalide")
        
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow(
                "SELECT role FROM utilisateur WHERE id_utilisateur = $1",
                user_id
            )
            if not row or row["role"] != "admin":
                raise HTTPException(status_code=403, detail="Accès non autorisé")
            return user_id
        finally:
            await conn.close()
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Token invalide")


@router.get("/admin/users")
async def get_all_users(token: str = Query(...)):
    """Récupère tous les utilisateurs (admin uniquement)"""
    await verifier_admin(token)
    
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        rows = await conn.fetch("""
            SELECT 
                id_utilisateur,
                nom,
                email,
                telephone,
                role,
                photo_profil,
                date_inscription,
                adresse
            FROM utilisateur
            ORDER BY id_utilisateur
        """)
        
        result = []
        for row in rows:
            result.append({
                "id": row["id_utilisateur"],
                "nom": row["nom"],
                "email": row["email"],
                "telephone": row["telephone"],
                "role": row["role"],
                "photo_profil": row["photo_profil"],
                "date_inscription": row["date_inscription"].isoformat() if row["date_inscription"] else None,
                "adresse": row["adresse"]
            })
        return result
    finally:
        await conn.close()


@router.get("/admin/users/{user_id}/stats")
async def get_user_stats(user_id: int, token: str = Query(...)):
    """Récupère les statistiques d'un utilisateur spécifique (admin uniquement)"""
    await verifier_admin(token)
    
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # ============================================================
        # RÉCUPÉRER TOUTES LES INFORMATIONS DE L'UTILISATEUR
        # ============================================================
        user = await conn.fetchrow("""
            SELECT 
                id_utilisateur,
                nom,
                email,
                telephone,
                role,
                photo_profil,
                date_inscription,
                adresse
            FROM utilisateur 
            WHERE id_utilisateur = $1
        """, user_id)
        
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        # Statistiques
        total_diagnostics = await conn.fetchval("""
            SELECT COUNT(*) FROM diagnostic WHERE id_utilisateur = $1
        """, user_id)
        
        total_parcelles = await conn.fetchval("""
            SELECT COUNT(*) FROM parcelle WHERE id_utilisateur = $1
        """, user_id)
        
        total_zones = await conn.fetchval("""
            SELECT COUNT(*) FROM zone_infectee WHERE id_utilisateur = $1
        """, user_id)
        
        total_observations = await conn.fetchval("""
            SELECT COUNT(*) FROM observation o
            JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
            WHERE d.id_utilisateur = $1
        """, user_id)
        
        # Répartition par maladie
        maladies = await conn.fetch("""
            SELECT 
                o.maladie_nom,
                COUNT(*) as count
            FROM observation o
            JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
            WHERE d.id_utilisateur = $1
            GROUP BY o.maladie_nom
            ORDER BY count DESC
        """, user_id)
        
        # Dernière activité
        derniere_activite = await conn.fetchrow("""
            SELECT date_debut FROM diagnostic
            WHERE id_utilisateur = $1
            ORDER BY date_debut DESC
            LIMIT 1
        """, user_id)
        
        # ============================================================
        # RETOURNER TOUTES LES INFORMATIONS
        # ============================================================
        return {
            "user": {
                "id": user["id_utilisateur"],
                "nom": user["nom"],
                "email": user["email"],
                "telephone": user["telephone"],
                "role": user["role"],
                "photo_profil": user["photo_profil"],
                "date_inscription": user["date_inscription"].isoformat() if user["date_inscription"] else None,
                "adresse": user["adresse"]
            },
            "total_diagnostics": total_diagnostics or 0,
            "total_parcelles": total_parcelles or 0,
            "total_zones": total_zones or 0,
            "total_observations": total_observations or 0,
            "maladies": [dict(m) for m in maladies],
            "derniere_activite": derniere_activite["date_debut"].isoformat() if derniere_activite else None
        }
    finally:
        await conn.close()


@router.delete("/admin/users/{user_id}")
async def delete_user(user_id: int, token: str = Query(...)):
    """Supprime un utilisateur et toutes ses données (admin uniquement)"""
    admin_id = await verifier_admin(token)
    
    if user_id == admin_id:
        raise HTTPException(status_code=400, detail="Vous ne pouvez pas vous supprimer vous-même")
    
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        # Vérifier que l'utilisateur existe
        user = await conn.fetchrow(
            "SELECT id_utilisateur FROM utilisateur WHERE id_utilisateur = $1",
            user_id
        )
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        # Supprimer en cascade (les clés étrangères ON DELETE CASCADE feront le travail)
        result = await conn.execute("DELETE FROM utilisateur WHERE id_utilisateur = $1", user_id)
        
        return {"status": "ok", "message": f"Utilisateur {user_id} supprimé"}
    finally:
        await conn.close()


@router.get("/admin/global-stats")
async def get_global_stats(token: str = Query(...)):
    """Récupère les statistiques globales de la plateforme (admin uniquement)"""
    await verifier_admin(token)
    
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        total_users = await conn.fetchval("SELECT COUNT(*) FROM utilisateur")
        total_diagnostics = await conn.fetchval("SELECT COUNT(*) FROM diagnostic")
        total_parcelles = await conn.fetchval("SELECT COUNT(*) FROM parcelle")
        total_zones = await conn.fetchval("SELECT COUNT(*) FROM zone_infectee")
        total_observations = await conn.fetchval("SELECT COUNT(*) FROM observation")
        
        # Top maladies
        top_maladies = await conn.fetch("""
            SELECT 
                maladie_nom,
                COUNT(*) as count
            FROM observation
            WHERE maladie_nom IS NOT NULL
            GROUP BY maladie_nom
            ORDER BY count DESC
            LIMIT 5
        """)
        
        # Évolution (par mois)
        evolution = await conn.fetch("""
            SELECT 
                DATE_TRUNC('month', date_debut) as mois,
                COUNT(*) as count
            FROM diagnostic
            GROUP BY DATE_TRUNC('month', date_debut)
            ORDER BY mois DESC
            LIMIT 6
        """)
        
        # Top utilisateurs (par diagnostics)
        top_users = await conn.fetch("""
            SELECT 
                u.id_utilisateur,
                u.nom,
                COUNT(d.id_diagnostic) as diagnostic_count
            FROM utilisateur u
            LEFT JOIN diagnostic d ON u.id_utilisateur = d.id_utilisateur
            GROUP BY u.id_utilisateur, u.nom
            ORDER BY diagnostic_count DESC
            LIMIT 5
        """)
        
        return {
            "total_users": total_users or 0,
            "total_diagnostics": total_diagnostics or 0,
            "total_parcelles": total_parcelles or 0,
            "total_zones": total_zones or 0,
            "total_observations": total_observations or 0,
            "top_maladies": [dict(m) for m in top_maladies],
            "evolution": [{"mois": str(r["mois"]), "count": r["count"]} for r in evolution[::-1]],
            "top_users": [dict(u) for u in top_users]
        }
    finally:
        await conn.close()
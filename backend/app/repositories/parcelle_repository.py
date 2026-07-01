import asyncpg
import json
from datetime import datetime, timedelta
from app.core.config import settings

class ParcelleRepository:
   
    async def creer_parcelle(self, id_utilisateur: int, nom: str, points: list) -> int:
        """Crée une nouvelle parcelle et retourne son ID"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            if len(points) < 3:
                raise ValueError("Une parcelle doit avoir au moins 3 points")
            
            polygon_points = list(points)
            if (abs(polygon_points[0][0] - polygon_points[-1][0]) > 0.000001 or
                abs(polygon_points[0][1] - polygon_points[-1][1]) > 0.000001):
                polygon_points.append(polygon_points[0])
            
            wkt_points = []
            for p in polygon_points:
                lat, lon = p[0], p[1]
                wkt_points.append(f"{lon} {lat}")
            wkt = f"POLYGON(({', '.join(wkt_points)}))"
            
            row = await conn.fetchrow("""
                INSERT INTO parcelle (id_utilisateur, nom, polygone, date_creation)
                VALUES ($1, $2, ST_GeomFromText($3, 4326), NOW())
                RETURNING id_parcelle
            """, id_utilisateur, nom, wkt)
            id_parcelle = row['id_parcelle']
            
            await conn.execute("""
                UPDATE observation
                SET id_parcelle = $1
                WHERE ST_Contains(
                    ST_GeomFromText($2, 4326),
                    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
                )
                AND id_parcelle IS NULL
            """, id_parcelle, wkt)
            
            await conn.execute("""
                UPDATE zone_infectee
                SET id_parcelle = $1, zone_type = 'DANS_PARCELLE'
                WHERE ST_Contains(
                    ST_GeomFromText($2, 4326),
                    ST_SetSRID(ST_MakePoint(centre_longitude, centre_latitude), 4326)
                )
                AND id_parcelle IS NULL
            """, id_parcelle, wkt)
            
            return id_parcelle
        finally:
            await conn.close()
    
    
    async def verifier_chevauchement(self, id_utilisateur: int, points: list) -> bool:
        """Vérifie si la nouvelle parcelle chevauche une parcelle existante"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            polygon_points = list(points)
            if (abs(polygon_points[0][0] - polygon_points[-1][0]) > 0.000001 or
                abs(polygon_points[0][1] - polygon_points[-1][1]) > 0.000001):
                polygon_points.append(polygon_points[0])
            
            wkt_points = []
            for p in polygon_points:
                lat, lon = p[0], p[1]
                wkt_points.append(f"{lon} {lat}")
            wkt = f"POLYGON(({', '.join(wkt_points)}))"
            
            row = await conn.fetchrow("""
                SELECT COUNT(*) FROM parcelle
                WHERE id_utilisateur = $1
                AND ST_Intersects(polygone, ST_GeomFromText($2, 4326))
            """, id_utilisateur, wkt)
            return row[0] > 0
        finally:
            await conn.close()


    async def supprimer_parcelle(self, id_parcelle: int) -> bool:
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            await conn.execute("UPDATE zone_infectee SET id_parcelle = NULL, zone_type = 'HORS_PARCELLE' WHERE id_parcelle = $1", id_parcelle)
            await conn.execute("UPDATE observation SET id_parcelle = NULL WHERE id_parcelle = $1", id_parcelle)
            result = await conn.execute("DELETE FROM parcelle WHERE id_parcelle = $1", id_parcelle)
            return int(result.split()[-1]) > 0
        finally:
            await conn.close()
    
    async def get_parcelles(self, id_utilisateur: int):
        """Récupère toutes les parcelles d'un utilisateur"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            rows = await conn.fetch("""
                SELECT 
                    id_parcelle,
                    nom,
                    ST_AsGeoJSON(polygone) as geojson,
                    ST_Area(polygone::geography) as surface_m2,
                    date_creation
                FROM parcelle
                WHERE id_utilisateur = $1
                ORDER BY id_parcelle DESC
            """, id_utilisateur)
            
            result = []
            for row in rows:
                surface_ha = row['surface_m2'] / 10000 if row['surface_m2'] else 0
                
                geojson_str = row['geojson']
                if geojson_str:
                    geojson = json.loads(geojson_str)
                    coordinates = geojson.get('coordinates', [])
                    if coordinates and len(coordinates) > 0:
                        points = []
                        for coord in coordinates[0]:
                            points.append([coord[1], coord[0]])
                    else:
                        points = []
                else:
                    points = []
                
                result.append({
                    'id': row['id_parcelle'],
                    'nom': row['nom'],
                    'points': points,
                    'surface_m2': round(float(row['surface_m2']), 2) if row['surface_m2'] else 0,
                    'surface_ha': round(float(surface_ha), 2),
                    'date_creation': str(row['date_creation']) if row['date_creation'] else None
                })
            return result
        finally:
            await conn.close()
    
    async def get_parcelle_by_id(self, id_parcelle: int):
        """Récupère une parcelle par son ID"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            row = await conn.fetchrow("""
                SELECT 
                    id_parcelle,
                    id_utilisateur,
                    nom,
                    ST_AsGeoJSON(polygone) as geojson,
                    ST_Area(polygone::geography) as surface_m2,
                    date_creation
                FROM parcelle
                WHERE id_parcelle = $1
            """, id_parcelle)
            
            if row:
                surface_ha = row['surface_m2'] / 10000 if row['surface_m2'] else 0
                
                geojson_str = row['geojson']
                if geojson_str:
                    geojson = json.loads(geojson_str)
                    coordinates = geojson.get('coordinates', [])
                    if coordinates and (len(coordinates) > 0):
                        points = []
                        for coord in coordinates[0]:
                            points.append([coord[1], coord[0]])
                    else:
                        points = []
                else:
                    points = []
                
                return {
                    'id': row['id_parcelle'],
                    'id_utilisateur': row['id_utilisateur'],
                    'nom': row['nom'],
                    'points': points,
                    'surface_m2': round(float(row['surface_m2']), 2) if row['surface_m2'] else 0,
                    'surface_ha': round(float(surface_ha), 2),
                    'date_creation': str(row['date_creation']) if row['date_creation'] else None
                }
            return None
        finally:
            await conn.close()
    
    async def calculer_taux_infection(
        self,
        id_parcelle: int,
        user_id: int = 1,
        periode: str = "30j",
        maladie: str | None = None,
    ):
        """Calcule le taux d'infection pour une parcelle spécifique"""
        conn = await asyncpg.connect(settings.DATABASE_URL)
        try:
            jours = {"7j": 7, "30j": 30, "90j": 90, "365j": 365}.get(periode, 30)
            date_debut = datetime.now() - timedelta(days=jours)

            obs_filters = [
                "o.id_parcelle = $1",
                "d.id_utilisateur = $2",
                "o.timestamp >= $3",
            ]
            params = [id_parcelle, user_id, date_debut]
            param_index = 4

            if maladie:
                obs_filters.append(f"o.maladie_nom = ${param_index}")
                params.append(maladie)
                param_index += 1

            where_clause = " AND ".join(obs_filters)

            total_obs = await conn.fetchval(f"""
                SELECT COUNT(*)
                FROM observation o
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE {where_clause}
            """, *params)
            
            malades_obs = await conn.fetchval(f"""
                SELECT COUNT(*)
                FROM observation o
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE {where_clause}
                AND o.maladie_nom IS NOT NULL
                AND o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable', 'Sain')
            """, *params)
            
            total = total_obs if total_obs else 0
            malades = malades_obs if malades_obs else 0
            taux_infection = (malades / total * 100) if total > 0 else 0
            
            maladies_stats = await conn.fetch(f"""
                SELECT 
                    o.maladie_nom as maladie_nom,
                    COUNT(*) as count
                FROM observation o
                JOIN diagnostic d ON o.id_diagnostic = d.id_diagnostic
                WHERE {where_clause}
                AND o.maladie_nom IS NOT NULL
                AND o.maladie_nom NOT IN ('Tomato_healthy', 'Non identifiable', 'Sain')
                GROUP BY o.maladie_nom
                ORDER BY count DESC
            """, *params)
            
            return {
                'id_parcelle': id_parcelle,
                'total_observations': total,
                'observations_malades': malades,
                'taux_infection': round(taux_infection, 2),
                'details_par_maladie': [dict(row) for row in maladies_stats]
            }
        finally:
            await conn.close()
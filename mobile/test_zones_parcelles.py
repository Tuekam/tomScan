#!/usr/bin/env python3
# backend/test_zones_parcelles.py

import asyncio
import asyncpg
import sys
from math import radians, sin, cos, sqrt, atan2

# Configuration de la base de données
DATABASE_URL = "postgresql://tuekam:jules100%40@localhost:5432/tomscan"

def distance_en_mètres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Formule de Haversine"""
    R = 6371000
    phi1 = radians(lat1)
    phi2 = radians(lat2)
    delta_phi = radians(lat2 - lat1)
    delta_lambda = radians(lon2 - lon1)

    a = sin(delta_phi/2)**2 + cos(phi1) * cos(phi2) * sin(delta_lambda/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c

async def trouver_parcelle_contenant_point(conn, lat: float, lon: float) -> dict | None:
    """Trouve la parcelle qui contient ce point"""
    row = await conn.fetchrow("""
        SELECT id_parcelle, nom 
        FROM parcelle 
        WHERE ST_Contains(polygone, ST_SetSRID(ST_MakePoint($1, $2), 4326))
        LIMIT 1
    """, lon, lat)
    return dict(row) if row else None

async def simuler_observation(conn, lat: float, lon: float, id_diagnostic: int = 1, maladie_nom: str = "Late_blight", confiance: float = 95.0):
    """Simule l'ajout d'une observation"""
    # Trouver la parcelle contenant le point
    parcelle = await trouver_parcelle_contenant_point(conn, lat, lon)
    
    # Insérer l'observation
    row = await conn.fetchrow("""
        INSERT INTO observation (id_diagnostic, id_maladie, timestamp, latitude, longitude, precision_gps, confiance, maladie_nom, id_parcelle)
        VALUES ($1, (SELECT id_maladie FROM maladie WHERE nom = $2), NOW(), $3, $4, 5.0, $5, $2, $6)
        RETURNING id_observation
    """, id_diagnostic, maladie_nom, lat, lon, confiance, parcelle['id_parcelle'] if parcelle else None)
    
    return {
        "id": row['id_observation'],
        "latitude": lat,
        "longitude": lon,
        "parcelle": parcelle['nom'] if parcelle else None,
        "id_parcelle": parcelle['id_parcelle'] if parcelle else None
    }

async def regrouper_observations(conn, rayon_m: float = 1.0) -> list:
    """Regroupe les observations par proximité"""
    observations = await conn.fetch("""
        SELECT id_observation, latitude, longitude, id_parcelle
        FROM observation
        ORDER BY id_observation
    """)
    
    observations_list = [dict(obs) for obs in observations]
    groupes = []
    
    for obs in observations_list:
        trouve = False
        for groupe in groupes:
            for membre in groupe:
                if distance_en_mètres(obs["latitude"], obs["longitude"],
                                      membre["latitude"], membre["longitude"]) <= rayon_m:
                    groupe.append(obs)
                    trouve = True
                    break
            if trouve:
                break
        if not trouve:
            groupes.append([obs])
    
    return groupes

async def creer_zone_depuis_groupe(conn, groupe: list, seuil: int = 10) -> dict:
    """Crée une zone à partir d'un groupe d'observations"""
    if len(groupe) < seuil:
        return {"zone_creee": False, "raison": f"Seulement {len(groupe)} observations (seuil {seuil})"}
    
    # Calculer le centre
    centre_lat = sum(o["latitude"] for o in groupe) / len(groupe)
    centre_lon = sum(o["longitude"] for o in groupe) / len(groupe)
    
    # Déterminer les parcelles concernées
    parcelles_concernees = set()
    for obs in groupe:
        if obs["id_parcelle"]:
            parcelles_concernees.add(obs["id_parcelle"])
    
    # Récupérer les noms des parcelles
    parcelles_noms = []
    for pid in parcelles_concernees:
        row = await conn.fetchrow("SELECT nom FROM parcelle WHERE id_parcelle = $1", pid)
        if row:
            parcelles_noms.append(row['nom'])
    
    # Déterminer le type de zone
    if len(parcelles_concernees) == 0:
        zone_type = "HORS_PARCELLE"
        niveau_alerte = "🟠 MOYENNE"
    elif len(parcelles_concernees) == 1:
        zone_type = "DANS_PARCELLE"
        niveau_alerte = "🔴 ÉLEVÉE"
    else:
        zone_type = "MULTI_PARCELLES"
        niveau_alerte = "🔴🔴 TRÈS ÉLEVÉE"
    
    # Insérer ou mettre à jour la zone
    existing = await conn.fetchrow("""
        SELECT id_zone FROM zone_infectee
        WHERE ST_DWithin(
            ST_SetSRID(ST_MakePoint(centre_longitude, centre_latitude), 4326),
            ST_SetSRID(ST_MakePoint($1, $2), 4326),
            5
        )
        LIMIT 1
    """, centre_lon, centre_lat)
    
    id_parcelle_unique = list(parcelles_concernees)[0] if len(parcelles_concernees) == 1 else None
    
    if existing:
        await conn.execute("""
            UPDATE zone_infectee 
            SET nombre_observations = nombre_observations + $1,
                centre_latitude = $2,
                centre_longitude = $3,
                id_parcelle = COALESCE($4, id_parcelle),
                zone_type = $5
            WHERE id_zone = $6
        """, len(groupe), centre_lat, centre_lon, id_parcelle_unique, zone_type, existing['id_zone'])
        id_zone = existing['id_zone']
    else:
        row = await conn.fetchrow("""
            INSERT INTO zone_infectee (centre_latitude, centre_longitude, rayon, nombre_observations, id_parcelle, zone_type)
            VALUES ($1, $2, 1.0, $3, $4, $5)
            RETURNING id_zone
        """, centre_lat, centre_lon, len(groupe), id_parcelle_unique, zone_type)
        id_zone = row['id_zone']
    
    return {
        "zone_creee": True,
        "id_zone": id_zone,
        "zone_type": zone_type,
        "niveau_alerte": niveau_alerte,
        "parcelles_concernees": list(parcelles_concernees),
        "parcelles_noms": parcelles_noms,
        "nombre_observations": len(groupe),
        "centre": {"lat": centre_lat, "lon": centre_lon}
    }

async def afficher_statistiques(conn):
    """Affiche les statistiques actuelles"""
    print("\n" + "="*60)
    print("📊 STATISTIQUES ACTUELLES")
    print("="*60)
    
    # Compter les observations
    obs_count = await conn.fetchval("SELECT COUNT(*) FROM observation")
    print(f"📝 Observations totales: {obs_count}")
    
    # Compter les zones
    zones = await conn.fetch("SELECT id_zone, zone_type, nombre_observations FROM zone_infectee")
    print(f"📍 Zones infectées: {len(zones)}")
    for zone in zones:
        print(f"   - Zone #{zone['id_zone']}: {zone['zone_type']} ({zone['nombre_observations']} obs)")
    
    # Observations par parcelle
    rows = await conn.fetch("""
        SELECT p.nom, COUNT(o.id_observation) as count
        FROM observation o
        LEFT JOIN parcelle p ON o.id_parcelle = p.id_parcelle
        GROUP BY p.nom
        ORDER BY count DESC
    """)
    print("\n🏞️ Observations par parcelle:")
    for row in rows:
        nom = row['nom'] if row['nom'] else "Hors parcelle"
        print(f"   - {nom}: {row['count']} obs")

async def main():
    print("🧪 TEST DE LA LOGIQUE ZONES/PARCELLES")
    print("="*60)
    
    conn = await asyncpg.connect(DATABASE_URL)
    
    try:
        # 1. Nettoyer les données de test
        print("\n🗑️ Nettoyage des données de test...")
        await conn.execute("DELETE FROM zone_infectee")
        await conn.execute("DELETE FROM observation")
        print("   ✅ Done")
        
        # 2. Afficher les parcelles existantes
        parcelles = await conn.fetch("SELECT id_parcelle, nom, ST_AsText(polygone) as wkt FROM parcelle")
        print("\n🏞️ Parcelles disponibles:")
        for p in parcelles:
            print(f"   - {p['nom']} (ID: {p['id_parcelle']})")
        
        if not parcelles:
            print("   ⚠️ AUCUNE PARCELLE TROUVÉE ! Veuillez d'abord créer des parcelles.")
            return
        
        # Récupérer les coordonnées approximatives des parcelles
        premiere_parcelle = parcelles[0]
        
        # 3. Simulation 1: Zone DANS une parcelle (12 observations)
        print("\n" + "="*60)
        print("🧪 SIMULATION 1: Zone DANS une parcelle (12 observations)")
        print("="*60)
        
        # Utiliser les coordonnées approximatives de la première parcelle
        # Pour simplifier, on prend des coordonnées autour du point (4.0515, 9.7679)
        base_lat = 4.0515
        base_lon = 9.7679
        
        for i in range(12):
            # Petite variation pour rester proche
            lat = base_lat + (i * 0.00001)
            lon = base_lon + (i * 0.00001)
            obs = await simuler_observation(conn, lat, lon, 1, "Late_blight", 95.0)
            print(f"   ✅ Observation #{obs['id']} à ({lat:.6f}, {lon:.6f}) - Parcelle: {obs['parcelle'] or 'Aucune'}")
        
        # Regrouper et créer les zones
        groupes = await regrouper_observations(conn, 1.0)
        print(f"\n📊 Groupes trouvés: {len(groupes)}")
        
        for i, groupe in enumerate(groupes):
            resultat = await creer_zone_depuis_groupe(conn, groupe, 10)
            if resultat['zone_creee']:
                print(f"\n   ✅ ZONE CRÉÉE #{resultat['id_zone']}:")
                print(f"      - Type: {resultat['zone_type']}")
                print(f"      - Alerte: {resultat['niveau_alerte']}")
                print(f"      - Observations: {resultat['nombre_observations']}")
                print(f"      - Parcelles: {resultat['parcelles_noms'] if resultat['parcelles_noms'] else 'Aucune'}")
        
        await afficher_statistiques(conn)
        
        # 4. Simulation 2: Zone HORS parcelle (15 observations)
        print("\n" + "="*60)
        print("🧪 SIMULATION 2: Zone HORS parcelle (15 observations)")
        print("="*60)
        
        # Coordonnées loin des parcelles existantes
        hors_lat = 4.1000
        hors_lon = 9.8000
        
        for i in range(15):
            lat = hors_lat + (i * 0.00001)
            lon = hors_lon + (i * 0.00001)
            obs = await simuler_observation(conn, lat, lon, 2, "Early_blight", 87.0)
            print(f"   ✅ Observation #{obs['id']} à ({lat:.6f}, {lon:.6f}) - Parcelle: {obs['parcelle'] or 'Aucune'}")
        
        groupes = await regrouper_observations(conn, 1.0)
        for i, groupe in enumerate(groupes):
            resultat = await creer_zone_depuis_groupe(conn, groupe, 10)
            if resultat['zone_creee']:
                print(f"\n   ✅ ZONE CRÉÉE #{resultat['id_zone']}:")
                print(f"      - Type: {resultat['zone_type']}")
                print(f"      - Alerte: {resultat['niveau_alerte']}")
                print(f"      - Observations: {resultat['nombre_observations']}")
        
        await afficher_statistiques(conn)
        
        # 5. Simulation 3: Trop peu d'observations (5 seulement)
        print("\n" + "="*60)
        print("🧪 SIMULATION 3: Pas assez d'observations (5 < seuil 10)")
        print("="*60)
        
        seuil_lat = 4.0600
        seuil_lon = 9.7900
        
        for i in range(5):
            lat = seuil_lat + (i * 0.00001)
            lon = seuil_lon + (i * 0.00001)
            obs = await simuler_observation(conn, lat, lon, 3, "Septoria_spot", 78.0)
            print(f"   ✅ Observation #{obs['id']} à ({lat:.6f}, {lon:.6f})")
        
        groupes = await regrouper_observations(conn, 1.0)
        for groupe in groupes:
            resultat = await creer_zone_depuis_groupe(conn, groupe, 10)
            if not resultat['zone_creee']:
                print(f"\n   ⚠️ {resultat['raison']}")
        
        await afficher_statistiques(conn)
        
        # 6. Vérification finale
        print("\n" + "="*60)
        print("📋 VÉRIFICATION FINALE")
        print("="*60)
        
        zones = await conn.fetch("""
            SELECT 
                z.id_zone,
                z.zone_type,
                z.nombre_observations,
                z.id_parcelle,
                p.nom as parcelle_nom
            FROM zone_infectee z
            LEFT JOIN parcelle p ON z.id_parcelle = p.id_parcelle
            ORDER BY z.id_zone
        """)
        
        print("\n📍 Zones infectées créées:")
        for zone in zones:
            print(f"   Zone #{zone['id_zone']}:")
            print(f"      - Type: {zone['zone_type']}")
            print(f"      - Observations: {zone['nombre_observations']}")
            print(f"      - Parcelle associée: {zone['parcelle_nom'] or 'Aucune'}")
        
        print("\n" + "="*60)
        print("✅ TESTS TERMINÉS")
        print("="*60)
        
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(main())

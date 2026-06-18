-- Table des utilisateurs
CREATE TABLE IF NOT EXISTS utilisateur (
    id_utilisateur SERIAL PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    mot_de_passe VARCHAR(255) NOT NULL,
    telephone VARCHAR(20),
    photo_profil TEXT,
    date_inscription TIMESTAMP DEFAULT NOW(),
    adresse TEXT,
    role VARCHAR(20) DEFAULT 'agriculteur'
);

-- Table des maladies (référentiel fixe)
CREATE TABLE IF NOT EXISTS maladie (
    id_maladie SERIAL PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    description TEXT,
    symptomes TEXT,
    recommandation TEXT,
    niveau_gravite VARCHAR(20),
    image_reference TEXT
);

-- Insérer les 6 classes
INSERT INTO maladie (nom, niveau_gravite) VALUES
('Tomato_Early_Blight', 'MOYEN'),
('Tomato_Healthy', 'FAIBLE'),
('Tomato_leaf_late_blight', 'ELEVE'),
('Tomato_leaf_yellow_curl_virus', 'MOYEN'),
('Tomato_mold_leaf', 'MOYEN'),
('Tomato_septora_leaf_spot', 'MOYEN')
ON CONFLICT (nom) DO NOTHING;

-- Table diagnostic (session)
CREATE TABLE IF NOT EXISTS diagnostic (
    id_diagnostic SERIAL PRIMARY KEY,
    id_utilisateur INTEGER REFERENCES utilisateur(id_utilisateur) ON DELETE CASCADE,
    date_debut TIMESTAMP NOT NULL,
    date_fin TIMESTAMP,
    mode_capture VARCHAR(20) NOT NULL
);

-- Table observation (analyse ponctuelle)
CREATE TABLE IF NOT EXISTS observation (
    id_observation SERIAL PRIMARY KEY,
    id_diagnostic INTEGER REFERENCES diagnostic(id_diagnostic) ON DELETE CASCADE,
    id_maladie INTEGER REFERENCES maladie(id_maladie),
    timestamp TIMESTAMP NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    precision_gps DOUBLE PRECISION,
    image_path TEXT,
    confiance DOUBLE PRECISION,
    maladie_nom VARCHAR(100)  -- pour stocker "Non identifiable" si besoin
);

-- Table zone infectée (regroupement spatial)
CREATE TABLE IF NOT EXISTS zone_infectee (
    id_zone SERIAL PRIMARY KEY,
    centre_latitude DOUBLE PRECISION NOT NULL,
    centre_longitude DOUBLE PRECISION NOT NULL,
    rayon DOUBLE PRECISION DEFAULT 3.0,
    nombre_observations INTEGER DEFAULT 0
);

-- Table conversation
CREATE TABLE IF NOT EXISTS conversation (
    id_conversation SERIAL PRIMARY KEY,
    id_utilisateur INTEGER REFERENCES utilisateur(id_utilisateur) ON DELETE CASCADE,
    date_creation TIMESTAMP DEFAULT NOW(),
    sujet VARCHAR(255)
);

-- Table message
CREATE TABLE IF NOT EXISTS message (
    id_message SERIAL PRIMARY KEY,
    id_conversation INTEGER REFERENCES conversation(id_conversation) ON DELETE CASCADE,
    question TEXT NOT NULL,
    reponse TEXT NOT NULL,
    date_message TIMESTAMP DEFAULT NOW()
);

CREATE TABLE notification (
    id_notification SERIAL PRIMARY KEY,
    id_utilisateur INTEGER REFERENCES utilisateur(id_utilisateur) ON DELETE CASCADE,
    titre VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    date_creation TIMESTAMP DEFAULT NOW(),
    lu BOOLEAN DEFAULT FALSE,
    type VARCHAR(50) NOT NULL
);

-- Créer un index spatial pour les recherches de proximité (PostGIS)
CREATE INDEX IF NOT EXISTS idx_observation_geog ON observation USING GIST (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326));
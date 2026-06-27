--
-- PostgreSQL database dump
--

\restrict yJHYOIq6C50xsVIcvmX9917EkSGPpFdk5DZvakh9z5n2U6PvWRmClKhxqCc7S2g

-- Dumped from database version 18.1 (Debian 18.1-2)
-- Dumped by pg_dump version 18.1 (Debian 18.1-2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: conversation; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.conversation (
    id_conversation integer NOT NULL,
    id_utilisateur integer,
    date_creation timestamp without time zone DEFAULT now(),
    sujet character varying(255)
);


ALTER TABLE public.conversation OWNER TO tuekam;

--
-- Name: conversation_id_conversation_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.conversation_id_conversation_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.conversation_id_conversation_seq OWNER TO tuekam;

--
-- Name: conversation_id_conversation_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.conversation_id_conversation_seq OWNED BY public.conversation.id_conversation;


--
-- Name: diagnostic; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.diagnostic (
    id_diagnostic integer NOT NULL,
    id_utilisateur integer,
    date_debut timestamp without time zone NOT NULL,
    date_fin timestamp without time zone,
    mode_capture character varying(20) NOT NULL,
    id_parcelle integer
);


ALTER TABLE public.diagnostic OWNER TO tuekam;

--
-- Name: diagnostic_id_diagnostic_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.diagnostic_id_diagnostic_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.diagnostic_id_diagnostic_seq OWNER TO tuekam;

--
-- Name: diagnostic_id_diagnostic_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.diagnostic_id_diagnostic_seq OWNED BY public.diagnostic.id_diagnostic;


--
-- Name: maladie; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.maladie (
    id_maladie integer NOT NULL,
    nom character varying(100) NOT NULL,
    description text,
    symptomes text,
    recommandation text,
    niveau_gravite character varying(20),
    image_reference text
);


ALTER TABLE public.maladie OWNER TO tuekam;

--
-- Name: maladie_id_maladie_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.maladie_id_maladie_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maladie_id_maladie_seq OWNER TO tuekam;

--
-- Name: maladie_id_maladie_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.maladie_id_maladie_seq OWNED BY public.maladie.id_maladie;


--
-- Name: message; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.message (
    id_message integer NOT NULL,
    id_conversation integer,
    question text NOT NULL,
    reponse text NOT NULL,
    date_message timestamp without time zone DEFAULT now()
);


ALTER TABLE public.message OWNER TO tuekam;

--
-- Name: message_id_message_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.message_id_message_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.message_id_message_seq OWNER TO tuekam;

--
-- Name: message_id_message_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.message_id_message_seq OWNED BY public.message.id_message;


--
-- Name: notification; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.notification (
    id_notification integer NOT NULL,
    id_utilisateur integer,
    titre character varying(255) NOT NULL,
    message text NOT NULL,
    date_creation timestamp without time zone DEFAULT now(),
    lu boolean DEFAULT false,
    type character varying(50) NOT NULL,
    id_zone integer,
    id_parcelle integer,
    latitude double precision,
    longitude double precision
);


ALTER TABLE public.notification OWNER TO tuekam;

--
-- Name: notification_id_notification_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.notification_id_notification_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notification_id_notification_seq OWNER TO tuekam;

--
-- Name: notification_id_notification_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.notification_id_notification_seq OWNED BY public.notification.id_notification;


--
-- Name: observation; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.observation (
    id_observation integer NOT NULL,
    id_diagnostic integer,
    id_maladie integer,
    "timestamp" timestamp without time zone NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    precision_gps double precision,
    image_path text,
    confiance double precision,
    maladie_nom character varying(100),
    id_parcelle integer
);


ALTER TABLE public.observation OWNER TO tuekam;

--
-- Name: observation_id_observation_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.observation_id_observation_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.observation_id_observation_seq OWNER TO tuekam;

--
-- Name: observation_id_observation_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.observation_id_observation_seq OWNED BY public.observation.id_observation;


--
-- Name: parcelle; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.parcelle (
    id_parcelle integer NOT NULL,
    id_utilisateur integer,
    nom character varying(100) NOT NULL,
    surface double precision,
    polygone public.geometry(Polygon,4326),
    date_creation timestamp without time zone DEFAULT now()
);


ALTER TABLE public.parcelle OWNER TO tuekam;

--
-- Name: parcelle_id_parcelle_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.parcelle_id_parcelle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.parcelle_id_parcelle_seq OWNER TO tuekam;

--
-- Name: parcelle_id_parcelle_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.parcelle_id_parcelle_seq OWNED BY public.parcelle.id_parcelle;


--
-- Name: session; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.session (
    id_session integer NOT NULL,
    id_utilisateur integer,
    date_debut timestamp without time zone NOT NULL,
    date_fin timestamp without time zone,
    mode character varying(20) DEFAULT 'TEMPS_REEL'::character varying,
    total_frames integer DEFAULT 0,
    frames_analysees integer DEFAULT 0,
    zones_crees integer DEFAULT 0,
    resume jsonb,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.session OWNER TO tuekam;

--
-- Name: session_id_session_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.session_id_session_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.session_id_session_seq OWNER TO tuekam;

--
-- Name: session_id_session_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.session_id_session_seq OWNED BY public.session.id_session;


--
-- Name: utilisateur; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.utilisateur (
    id_utilisateur integer NOT NULL,
    nom character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    mot_de_passe character varying(255) NOT NULL,
    telephone character varying(20),
    photo_profil text,
    date_inscription timestamp without time zone DEFAULT now(),
    adresse text,
    role character varying(20) DEFAULT 'agriculteur'::character varying
);


ALTER TABLE public.utilisateur OWNER TO tuekam;

--
-- Name: utilisateur_id_utilisateur_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.utilisateur_id_utilisateur_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.utilisateur_id_utilisateur_seq OWNER TO tuekam;

--
-- Name: utilisateur_id_utilisateur_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.utilisateur_id_utilisateur_seq OWNED BY public.utilisateur.id_utilisateur;


--
-- Name: zone_infectee; Type: TABLE; Schema: public; Owner: tuekam
--

CREATE TABLE public.zone_infectee (
    id_zone integer NOT NULL,
    centre_latitude double precision NOT NULL,
    centre_longitude double precision NOT NULL,
    rayon double precision DEFAULT 3.0,
    nombre_observations integer DEFAULT 0,
    id_parcelle integer,
    zone_type character varying(50) DEFAULT 'HORS_PARCELLE'::character varying,
    id_utilisateur integer
);


ALTER TABLE public.zone_infectee OWNER TO tuekam;

--
-- Name: zone_infectee_id_zone_seq; Type: SEQUENCE; Schema: public; Owner: tuekam
--

CREATE SEQUENCE public.zone_infectee_id_zone_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.zone_infectee_id_zone_seq OWNER TO tuekam;

--
-- Name: zone_infectee_id_zone_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tuekam
--

ALTER SEQUENCE public.zone_infectee_id_zone_seq OWNED BY public.zone_infectee.id_zone;


--
-- Name: conversation id_conversation; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.conversation ALTER COLUMN id_conversation SET DEFAULT nextval('public.conversation_id_conversation_seq'::regclass);


--
-- Name: diagnostic id_diagnostic; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.diagnostic ALTER COLUMN id_diagnostic SET DEFAULT nextval('public.diagnostic_id_diagnostic_seq'::regclass);


--
-- Name: maladie id_maladie; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.maladie ALTER COLUMN id_maladie SET DEFAULT nextval('public.maladie_id_maladie_seq'::regclass);


--
-- Name: message id_message; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.message ALTER COLUMN id_message SET DEFAULT nextval('public.message_id_message_seq'::regclass);


--
-- Name: notification id_notification; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.notification ALTER COLUMN id_notification SET DEFAULT nextval('public.notification_id_notification_seq'::regclass);


--
-- Name: observation id_observation; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.observation ALTER COLUMN id_observation SET DEFAULT nextval('public.observation_id_observation_seq'::regclass);


--
-- Name: parcelle id_parcelle; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.parcelle ALTER COLUMN id_parcelle SET DEFAULT nextval('public.parcelle_id_parcelle_seq'::regclass);


--
-- Name: session id_session; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.session ALTER COLUMN id_session SET DEFAULT nextval('public.session_id_session_seq'::regclass);


--
-- Name: utilisateur id_utilisateur; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.utilisateur ALTER COLUMN id_utilisateur SET DEFAULT nextval('public.utilisateur_id_utilisateur_seq'::regclass);


--
-- Name: zone_infectee id_zone; Type: DEFAULT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.zone_infectee ALTER COLUMN id_zone SET DEFAULT nextval('public.zone_infectee_id_zone_seq'::regclass);


--
-- Data for Name: conversation; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.conversation (id_conversation, id_utilisateur, date_creation, sujet) FROM stdin;
8	28	2026-06-22 17:31:21.799477	sujet 1
10	30	2026-06-22 19:04:55.163586	sujet mildiu
11	31	2026-06-23 13:25:21.444603	mildiu
\.


--
-- Data for Name: diagnostic; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.diagnostic (id_diagnostic, id_utilisateur, date_debut, date_fin, mode_capture, id_parcelle) FROM stdin;
1174	27	2026-06-22 12:39:49.587937	\N	PHOTO	\N
1175	27	2026-06-22 12:40:45.287417	\N	PHOTO	\N
1176	28	2026-06-22 12:43:04.518852	\N	PHOTO	\N
1178	28	2026-06-22 13:25:12.064413	\N	PHOTO	\N
1179	28	2026-06-22 18:55:14.15689	\N	PHOTO	\N
1180	30	2026-06-22 19:03:37.306673	\N	PHOTO	\N
1181	30	2026-06-22 19:09:39.856737	\N	PHOTO	\N
1182	31	2026-06-23 13:22:27.920379	\N	PHOTO	\N
1183	31	2026-06-23 13:23:39.797636	\N	PHOTO	\N
1184	31	2026-06-23 13:24:49.060496	\N	PHOTO	\N
1185	31	2026-06-23 17:59:26.75309	\N	PHOTO	\N
1186	31	2026-06-23 18:00:44.101033	\N	PHOTO	\N
1187	31	2026-06-23 23:09:09.176304	\N	PHOTO	\N
1188	31	2026-06-23 23:10:05.98984	\N	PHOTO	\N
1189	31	2026-06-23 23:10:28.159694	\N	PHOTO	\N
1190	33	2026-06-24 08:19:31.815656	\N	PHOTO	\N
1191	33	2026-06-24 08:23:34.607814	\N	PHOTO	\N
1192	33	2026-06-24 08:23:35.341567	\N	PHOTO	\N
1193	33	2026-06-24 08:23:36.033194	\N	PHOTO	\N
1194	33	2026-06-24 08:23:36.755474	\N	PHOTO	\N
1195	33	2026-06-24 08:23:37.522837	\N	PHOTO	\N
1196	33	2026-06-24 08:23:38.494782	\N	PHOTO	\N
1197	33	2026-06-24 08:23:39.468072	\N	PHOTO	\N
1198	33	2026-06-24 08:23:40.796481	\N	PHOTO	\N
1199	33	2026-06-24 08:23:41.948437	\N	PHOTO	\N
1200	33	2026-06-24 08:23:42.849268	\N	PHOTO	\N
1201	33	2026-06-24 08:23:43.787441	\N	PHOTO	\N
1202	33	2026-06-24 08:23:44.688704	\N	PHOTO	\N
1203	31	2026-06-24 10:26:18.930072	\N	PHOTO	\N
1204	31	2026-06-24 10:26:54.768359	\N	PHOTO	\N
1205	31	2026-06-24 10:28:10.597993	\N	PHOTO	\N
1206	31	2026-06-24 10:29:13.246909	\N	PHOTO	\N
1207	31	2026-06-24 10:56:04.237394	\N	PHOTO	\N
1208	31	2026-06-24 10:56:45.28164	\N	PHOTO	\N
1209	31	2026-06-24 10:57:35.985144	\N	PHOTO	\N
1210	31	2026-06-24 10:57:56.202807	\N	PHOTO	\N
1211	31	2026-06-24 10:59:35.082099	\N	PHOTO	\N
1212	31	2026-06-24 11:00:12.081807	\N	PHOTO	\N
1213	31	2026-06-24 21:31:14.322974	\N	PHOTO	\N
1215	31	2026-06-24 22:23:47.954875	\N	TEMPS_REEL	\N
1216	31	2026-06-24 22:23:52.089244	\N	TEMPS_REEL	\N
1217	31	2026-06-24 22:23:52.793012	\N	TEMPS_REEL	\N
1218	31	2026-06-24 22:23:53.840983	\N	TEMPS_REEL	\N
1219	31	2026-06-24 22:23:54.724324	\N	TEMPS_REEL	\N
1220	31	2026-06-24 22:23:54.757217	\N	TEMPS_REEL	\N
1221	31	2026-06-24 22:23:54.968774	\N	TEMPS_REEL	\N
1222	31	2026-06-24 22:23:55.86674	\N	TEMPS_REEL	\N
1223	31	2026-06-24 22:23:55.938793	\N	TEMPS_REEL	\N
1224	31	2026-06-24 22:23:55.941468	\N	TEMPS_REEL	\N
1225	31	2026-06-24 22:23:57.644058	\N	TEMPS_REEL	\N
1226	31	2026-06-24 22:24:01.450464	\N	TEMPS_REEL	\N
1227	31	2026-06-24 22:24:02.594094	\N	TEMPS_REEL	\N
1228	31	2026-06-24 22:24:02.593983	\N	TEMPS_REEL	\N
1229	31	2026-06-24 22:24:02.596955	\N	TEMPS_REEL	\N
1230	31	2026-06-24 22:24:03.536933	\N	TEMPS_REEL	\N
1231	31	2026-06-24 22:24:04.438048	\N	TEMPS_REEL	\N
1232	31	2026-06-24 22:24:05.51106	\N	TEMPS_REEL	\N
1233	31	2026-06-24 22:24:06.732492	\N	TEMPS_REEL	\N
1234	31	2026-06-24 22:24:07.542648	\N	TEMPS_REEL	\N
1235	31	2026-06-24 22:39:53.73739	\N	TEMPS_REEL	\N
1236	31	2026-06-24 22:39:56.69141	\N	TEMPS_REEL	\N
1237	31	2026-06-24 22:39:56.691985	\N	TEMPS_REEL	\N
1238	31	2026-06-24 22:39:57.024213	\N	TEMPS_REEL	\N
1239	31	2026-06-24 22:39:57.076766	\N	TEMPS_REEL	\N
1240	31	2026-06-24 22:39:57.655912	\N	TEMPS_REEL	\N
1241	31	2026-06-24 22:39:59.722376	\N	TEMPS_REEL	\N
1242	31	2026-06-24 22:40:01.475032	\N	TEMPS_REEL	\N
1243	31	2026-06-24 22:40:02.811681	\N	TEMPS_REEL	\N
1244	31	2026-06-24 22:40:03.674126	\N	TEMPS_REEL	\N
1245	31	2026-06-24 22:40:04.994347	\N	TEMPS_REEL	\N
1246	31	2026-06-24 22:40:05.88972	\N	TEMPS_REEL	\N
1247	31	2026-06-24 22:40:06.780239	\N	TEMPS_REEL	\N
1248	31	2026-06-24 22:40:08.627642	\N	TEMPS_REEL	\N
1249	31	2026-06-24 22:40:10.728012	\N	TEMPS_REEL	\N
1250	31	2026-06-24 22:40:12.68533	\N	TEMPS_REEL	\N
1251	31	2026-06-24 22:40:13.791988	\N	TEMPS_REEL	\N
1252	31	2026-06-24 22:40:15.589586	\N	TEMPS_REEL	\N
1253	31	2026-06-24 22:40:15.593123	\N	TEMPS_REEL	\N
1254	31	2026-06-25 08:33:44.49898	\N	PHOTO	\N
1255	31	2026-06-25 09:17:29.946138	\N	PHOTO	\N
1256	34	2026-06-25 13:05:02.623932	\N	TEMPS_REEL	\N
1257	34	2026-06-25 13:05:03.450352	\N	TEMPS_REEL	\N
1258	34	2026-06-25 13:05:06.074227	\N	TEMPS_REEL	\N
1259	34	2026-06-25 13:05:07.969845	\N	TEMPS_REEL	\N
1260	34	2026-06-25 13:05:22.50404	\N	TEMPS_REEL	\N
1261	34	2026-06-25 13:05:23.528936	\N	TEMPS_REEL	\N
1262	34	2026-06-25 13:05:25.984121	\N	TEMPS_REEL	\N
1263	34	2026-06-25 13:05:26.916591	\N	TEMPS_REEL	\N
1264	34	2026-06-25 15:00:37.550294	\N	PHOTO	\N
\.


--
-- Data for Name: maladie; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.maladie (id_maladie, nom, description, symptomes, recommandation, niveau_gravite, image_reference) FROM stdin;
4	Tomato_leaf_yellow_curl_virus	Le virus de l'enroulement jaune des feuilles de tomate (TYLCV) transmis par les aleurodes. Pertes jusqu'à 100%.	• Enroulement vers le haut des jeunes feuilles\\n• Jaunissement entre les nervures\\n• Rabougrissement\\n• Chute des fleurs	✅ Variétés résistantes\\n✅ Lutte contre les aleurodes (pièges jaunes, insecticides bio)\\n✅ Filets anti-insectes\\n✅ Éliminer les plants infectés	ELEVE	
3	Tomato_leaf_late_blight	Le mildiou est une maladie dévastatrice causée par Phytophthora infestans. Détruit une culture en quelques jours.	• Grandes taches brunes sur les feuilles\\n• Duvet blanc sous les feuilles\\n• Taches brunes sur les tiges\\n• Fruits avec taches brunes	✅ Bouillie bordelaise dès les premiers symptômes\\n✅ Retirer et brûler les plants infectés\\n✅ Arroser au pied\\n✅ Espacer les plants	ELEVE	
5	Tomato_mold_leaf	La moisissure grise (Botrytis cinerea) attaque en serre ou temps humide.	• Taches grises\\n• Pourriture grise duveteuse\\n• Fruits mous	✅ Améliorer la ventilation\\n✅ Réduire l'humidité\\n✅ Enlever les parties infectées\\n✅ Traiter avec fongicides bio	MOYEN	
6	Tomato_septoria_leaf_spot	La septoriose (Septoria lycopersici) attaque les feuilles basses.	• Petites taches grises à bord brun\\n• Points noirs au centre\\n• Jaunissement\\n• Chute des feuilles	✅ Fongicide à base de cuivre\\n✅ Retirer les feuilles atteintes\\n✅ Rotation des cultures\\n✅ Paillage\\n✅ Espacer les plants	MOYEN	
1	Tomato_Early_Blight	L'alternariose est une maladie fongique courante de la tomate causée par Alternaria solani. Elle se développe généralement sur les plants âgés ou stressés, par temps chaud et humide (25-30°C).	• Taches brunes circulaires sur les feuilles inférieures, avec des cercles concentriques (œil de grenouille)\\n• Jaunissement et chute prématurée des feuilles\\n• Taches noires sur les tiges et les fruits	✅ Appliquer des fongicides à base de cuivre (bouillie bordelaise)\\n✅ Retirer et brûler les feuilles infectées\\n✅ Pailler le sol\\n✅ Rotation des cultures sur 3 ans\\n✅ Arroser au pied sans mouiller le feuillage	MOYEN	
2	Tomato_Healthy	Feuille de tomate en parfaite santé, sans signe de maladie ou de stress.	• Feuilles vertes uniformes\\n• Absence de taches\\n• Bon développement	✅ Continuer les bonnes pratiques agricoles\\n✅ Rotation des cultures\\n✅ Surveillance régulière	FAIBLE	
\.


--
-- Data for Name: message; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.message (id_message, id_conversation, question, reponse, date_message) FROM stdin;
62	8	bonjour	Bonjour ! Je suis **TomScan AI**, votre assistant pour les maladies de la tomate au Cameroun. À votre service pour des conseils rapides et adaptés. 🌱🍅\n\nDites-moi ce dont vous avez besoin.	2026-06-22 17:31:27.485998
63	8	j'ai mal au dos	Hors contexte. Concentrez-vous sur vos tomates ! 🌱 Si problème de culture, je suis là.	2026-06-22 17:31:56.120567
64	8	je veux les noms communautaire des maladies comme septoria, mold leaf, early bligh, yellow curl	Voici les noms locaux au Cameroun :\n\n- **Septoriose** → *"Maladie des taches noires"* ou *"Poussière noire"* (selon région).\n- **Mildiou (Late blight)** → *"Feuille brûlée"* ou *"Maladie de la moisissure grise"*.\n- **Early blight** → *"Taches brunes"* (confondu parfois avec septoriose).\n- **Jaunissement/curling (Virus Y, TYLCV)** → *"Feuille qui se roule"* ou *"Tomate qui jaunit"*.\n\nBesoin de traitement ? Dites-moi la maladie précise.	2026-06-22 17:33:05.378631
69	8	Ma plante est atteinte d'une moisissure	**Mildiou (Late blight)** → *"Feuille brûlée"* ou *"Poussière grise"*.\n\n**Solution rapide (Cameroun)** :\n- **Bouillie bordelaise** (10 g/L) ou **purin d’ortie** (1 kg/10 L).\n- **Évitez l’excès d’eau** sur les feuilles.\n- **Arrosez au pied** le matin.\n\nVérifiez si c’est **vert-de-gris** (moisissure grise) ou **taches brunes** (autre maladie).	2026-06-22 18:57:49.803343
70	8	Je viens de diagnostiquer leaf yellow curl virus sur mes tomates. Que dois-je faire ?	**Yellow Leaf Curl Virus (TYLCV)** → *"Feuille qui se roule et jaunit"* (très contagieux).\n\n**Actions urgentes (Cameroun)** :\n1. **Détruisez les plantes infectées** (brûlez-les hors champ).\n2. **Éliminez les pucerons** (insectes vecteurs) avec du **savon noir** (50 g/L) ou **poussière de tabac**.\n3. **Protégez les plants sains** :\n   - **Filets anti-pucerons** (maille fine).\n   - **Rotations de cultures** (évitez les solanacées 2 ans après tomates).\n4. **Plantes résistantes** : Privilégiez les variétés comme *"Dzembe"* ou *"Merveille de Noël"* (moins sensibles).\n\n**À éviter** : Pulvérisations d’eau sur les feuilles (favorise les pucerons).	2026-06-22 19:00:09.965199
71	10	bonjour	Bonjour ! Je suis TomScan AI, ton assistant pour les maladies de la tomate au Cameroun. Comment puis-je t'aider aujourd'hui ? 🌱	2026-06-22 19:05:04.120113
72	10	oui ma plante est affecté de septoria spot	**Symptômes typiques :**\n- Taches brunes/grisâtres avec un halo jaune sur les feuilles.\n- Centre des taches devient poudreux (spores).\n\n**Solutions rapides :**\n1. **Éliminez** les feuilles infectées (brûlez-les).\n2. **Bouillie bordelaise** (10g/L) ou **cuivre** (2g/L) en pulvérisation préventive/ curative.\n3. **Évitez l’eau sur le feuillage** (arrosage au pied).\n4. **Rotation des cultures** (ne replantez pas tomate au même endroit avant 2–3 ans).\n\n**Variétés résistantes :** Privilégiez *Solana* ou *Bintje* si disponibles en semences locales.\n\n*À surveiller :* Humidité élevée et feuilles humides favorisent la maladie.	2026-06-22 19:05:31.080835
73	10	ok merci	Avec plaisir ! 🌱 Si besoin d’autres conseils, je suis là. Bonne récolte ! 🍅	2026-06-22 19:05:50.10175
74	11	Je viens de diagnostiquer leaf yellow curl virus sur mes tomates. Que dois-je faire ?	**Actions urgentes pour *TomScan AI* :**\n\n1. **Éliminez les plantes infectées** : Détruyez-les (brûlez ou enterrez) pour éviter la propagation.\n2. **Désinfectez** : Traitez les outils et les mains avec de l’eau de Javel (10%).\n3. **Contrôle des pucerons** : Utilisez du **savon noir** (10g/L) ou **pyrethre** (spray) pour éliminer les vecteurs.\n4. **Paillage** : Couvrez le sol avec du **paille** ou **herbes locales** (ex. *Andropogon gayanus*) pour limiter les pucerons.\n5. **Variétés résistantes** : Plantez des semences locales adaptées (ex. *tomate ‘Boubou’*).\n6. **Rotation** : Ne replantez pas de tomates au même endroit avant **6 mois**.\n\n**À éviter** : Fumure azotée excessive (favorise le virus).	2026-06-23 13:25:44.322702
75	11	Je viens de diagnostiquer leaf yellow curl virus sur mes tomates. Que dois-je faire ?	**Actions immédiates :**\n1. **Arrachez et brûlez** les plants infectés.\n2. **Traitez les pucerons** avec **savon noir** (10g/L d’eau) ou **neem** (1 c. à soupe/L).\n3. **Paillage** : Utilisez de la **paille** ou des feuilles sèches pour bloquer les pucerons.\n4. **Désinfectez** les outils avec de l’eau de Javel (10%).\n5. **Évitez les semences commerciales** : Privilégiez les variétés locales résistantes (*ex. tomate ‘Boubou’*).\n6. **Rotation** : Ne replantez pas de tomates au même endroit avant **6 mois**.\n\n**Astuce locale** : Vaporisez du **jus de citron + eau (1:10)** pour décourager les pucerons.	2026-06-23 13:26:05.152891
76	11	je veux aller en France	Hors contexte. Concentrez-vous sur vos tomates ! 🍅	2026-06-23 13:26:41.367655
77	11	Je viens de diagnostiquer mold leaf sur mes tomates. Que dois-je faire ?	**Pour *Alternaria* (mildiou des feuilles/tomates) :**\n\n1. **Éliminez** les feuilles/parts atteintes.\n2. **Traitement naturel** :\n   - **Bouillie bordelaise** (1%, 10g/L de sulfate de cuivre + chaux).\n   - **Poudre de soufre** (20g/L d’eau, le soir).\n3. **Rotation** : Attendez **4-6 mois** avant de replanter.\n4. **Évitez l’arrosage foliaire** : Arrosez au pied tôt le matin.\n5. **Paillage** : Utilisez de la **paille** ou des feuilles sèches pour limiter l’humidité.\n\n**Variétés résistantes** : Préférez les semences locales adaptées (ex. *tomate ‘Ndolé’*).	2026-06-23 18:01:12.835155
78	11	Je viens de diagnostiquer mold leaf sur mes tomates. Que dois-je faire ?	**Actions rapides :**\n- **Coupez** les feuilles/noeuds infectés (brûlez-les).\n- **Traitement** :\n  - **Bouillie bordelaise** (1% : 10g/L de sulfate de cuivre + chaux).\n  - **Poudre de soufre** (20g/L, le soir).\n- **Évitez** l’eau sur les feuilles (arrosez au sol tôt le matin).\n- **Espacez** les plants pour une bonne aération.\n- **Rotation** : Attendez **4-6 mois** avant de replanter.\n\n**Alternative locale** : Vaporisez du **jus de citron + eau (1:10)** pour limiter les spores.	2026-06-23 18:01:48.186338
79	11	idée de business à lancer au Cameroun	Hors contexte. Concentrez-vous sur les **maladies des tomates** ! 🌱🍅\n\n*(Ex. : "Comment traiter le *Verticillium* sur mes tomates ?")*	2026-06-23 18:03:10.830905
80	11	parle moi des maladies du cacao	Hors contexte. **TomScan AI** est spécialisé uniquement dans les **maladies des tomates** au Cameroun. 🍅🌱\n\n*(Ex. : "Comment traiter la *Fusariose* sur mes tomates ?")*	2026-06-23 18:04:12.650051
81	11	Je viens de diagnostiquer Early Blight sur mes tomates. Que dois-je faire ?	**Traitement pour *Early Blight* (Alternaria solani) :**\n\n1. **Éliminez** les feuilles/parts atteintes (brûlez-les).\n2. **Traitement** :\n   - **Bouillie bordelaise** (1%, 10g/L).\n   - **Poudre de soufre** (20g/L, le soir).\n3. **Rotation** : Attendez **3-4 mois** avant de replanter.\n4. **Évitez** l’arrosage foliaire (arrosez au pied tôt le matin).\n5. **Paillage** : Utilisez de la **paille** ou des feuilles sèches.\n6. **Prévention** : Espacez les plants pour une bonne circulation d’air.\n\n**Astuce locale** : Vaporisez du **jus de citron + eau (1:10)** pour limiter la propagation.	2026-06-25 08:39:59.902258
82	11	bonjour	Bonjour ! 🌱\n**Besoin d’aide pour vos tomates ?** Dites-moi la maladie (ex. : *Fusariose*, *Mosaïque*, *Oïdium*).	2026-06-25 11:55:57.699808
83	11	oui au cameroun certain jardinier ont un nom pour une maladie de tomate , ils appenlent ca attack	Au Cameroun, certains termes locaux pour maladies de tomate :\n\n- **"Attaque de *Kwé-Kwé*"** → *Mildiou* (Alternaria ou *Phytophthora*).\n- **"Feuilles qui deviennent jaunes et se roulent"** → *Virus de la jaunisse* (ex. *Tomato Yellow Leaf Curl Virus*).\n- **"Taches brunes avec un cercle jaune"** → *Early Blight* (Alternaria).\n- **"Feuilles qui noircissent et tombent"** → *Fusariose* ou *Verticillium*.\n\n**Solution générale** :\n- **Bouillie bordelaise** (1%) ou **poudre de soufre** (20g/L).\n- **Éliminez** les parties infectées.	2026-06-25 11:56:38.588702
\.


--
-- Data for Name: notification; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.notification (id_notification, id_utilisateur, titre, message, date_creation, lu, type, id_zone, id_parcelle, latitude, longitude) FROM stdin;
14	33	📍 Nouvelle zone émergente	Une nouvelle zone infectée émergente a été détectée avec 6 observations. Surveillance recommandée. Maladie dominante: leaf yellow curl virus.	2026-06-24 08:23:38.209651	f	zone_creee	65	\N	4.05107	9.76788
17	31	⚠️ Zone active détectée	Une zone infectée active a été détectée avec 17 observations. Traitement recommandé. Maladie dominante: Healthy.	2026-06-24 22:40:15.010282	t	zone_creee	68	\N	5.3545172647058825	10.425597935294117
16	31	⚠️ Zone active détectée	Une zone infectée active a été détectée avec 19 observations. Traitement recommandé. Maladie dominante: Healthy.	2026-06-24 22:24:07.274086	t	zone_creee	67	\N	5.3545175	10.42559785263158
15	31	📍 Nouvelle zone émergente	Une nouvelle zone infectée émergente a été détectée avec 6 observations. Surveillance recommandée. Maladie dominante: Healthy.	2026-06-24 11:00:13.361621	t	zone_creee	66	\N	5.335757699999999	10.434056733333334
19	34	📍 Nouvelle zone émergente	Une nouvelle zone infectée émergente a été détectée avec 8 observations. Surveillance recommandée. Maladie dominante: Early Blight.	2026-06-25 15:00:39.399817	f	zone_creee	70	\N	5.37777005	10.421588700000001
\.


--
-- Data for Name: observation; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.observation (id_observation, id_diagnostic, id_maladie, "timestamp", latitude, longitude, precision_gps, image_path, confiance, maladie_nom, id_parcelle) FROM stdin;
1320	1256	1	2026-06-25 13:05:02.667654	5.3777759	10.4215765	7.834000110626221		61.605942249298096	Tomato_Early_Blight	\N
1321	1257	1	2026-06-25 13:05:03.496899	5.3777759	10.4215765	7.834000110626221		54.65342402458191	Tomato_Early_Blight	\N
1322	1258	1	2026-06-25 13:05:06.120958	5.3777759	10.4215765	7.834000110626221		66.31379127502441	Tomato_Early_Blight	\N
1323	1259	2	2026-06-25 13:05:08.019034	5.3777759	10.4215765	7.834000110626221		84.90433692932129	Tomato_Healthy	\N
1324	1260	1	2026-06-25 13:05:22.548442	5.3777642	10.4216009	0.7419999837875366		82.42872953414917	Tomato_Early_Blight	\N
1325	1261	1	2026-06-25 13:05:23.575567	5.3777642	10.4216009	0.7419999837875366		83.8182270526886	Tomato_Early_Blight	\N
1326	1262	1	2026-06-25 13:05:26.026663	5.3777642	10.4216009	0.7419999837875366		83.47240090370178	Tomato_Early_Blight	\N
1327	1263	1	2026-06-25 13:05:26.963144	5.3777642	10.4216009	0.7419999837875366		87.13446855545044	Tomato_Early_Blight	\N
1328	1264	\N	2026-06-25 15:00:38.948329	5.3771965	10.4191122	600	uploads/ec5fb773-d30e-4648-af2b-b7ef8927b43f.jpg	99.78546500205994	Tomato_septora_leaf_spot	\N
\.


--
-- Data for Name: parcelle; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.parcelle (id_parcelle, id_utilisateur, nom, surface, polygone, date_creation) FROM stdin;
46	31	u	\N	0103000020E610000001000000050000002445823931DA2440F869BB56C56B1540233D43293DDA2440518169BF416A1540232DD2ACA3DA244073AD1385756A1540244DD24AA9DA2440618348F7926B15402445823931DA2440F869BB56C56B1540	2026-06-25 12:16:14.985895
\.


--
-- Data for Name: session; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.session (id_session, id_utilisateur, date_debut, date_fin, mode, total_frames, frames_analysees, zones_crees, resume, created_at) FROM stdin;
27	31	2026-06-24 22:23:42.34325	2026-06-24 22:24:07.590512	TEMPS_REEL	19	19	1	{"zones": [{"id_zone": 67, "maladies": {"Tomato_Healthy": 18, "Tomato_leaf_late_blight": 1}, "observations": 19}], "duree_secondes": 24.8, "maladies_stats": {"Tomato_Healthy": 18, "Tomato_leaf_late_blight": 1}, "total_observations": 19}	2026-06-24 22:24:07.59075
28	31	2026-06-24 22:39:51.39283	2026-06-24 22:40:15.512356	TEMPS_REEL	22	17	1	{"zones": [{"id_zone": 68, "maladies": {"Tomato_Healthy": 16, "Tomato_leaf_late_blight": 1}, "observations": 17}], "duree_secondes": 23.5, "maladies_stats": {"Tomato_Healthy": 16, "Tomato_leaf_late_blight": 1}, "total_observations": 17}	2026-06-24 22:40:15.512741
29	34	2026-06-25 13:04:49.97403	2026-06-25 13:05:33.634667	TEMPS_REEL	46	8	1	{"zones": [{"id_zone": 69, "maladies": {"Tomato_Healthy": 1, "Tomato_Early_Blight": 7}, "observations": 8}], "duree_secondes": 43.5, "maladies_stats": {"Tomato_Healthy": 1, "Tomato_Early_Blight": 7}, "total_observations": 8}	2026-06-25 13:05:33.634834
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: utilisateur; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.utilisateur (id_utilisateur, nom, email, mot_de_passe, telephone, photo_profil, date_inscription, adresse, role) FROM stdin;
27	Tuekam jules	jules@gmail.com	$2b$12$wZGP/DxJMwHWKDoJrvZ4NOHRUeDsKfHd6OM7NEVLP1mCugLxNtelG	699724329	\N	2026-06-22 12:37:58.436388	Douala Cameroun	agriculteur
28	Tuekam serge	sergemartial461@gmail.com	$2b$12$3VZISBgnmqOxgP/PC0JRG.1rRs7wty3kAepyxhTZMgv2eL0VhlF1O	695741425	/api/images/profils/profile_28.jpg	2026-06-22 12:42:19.03734	Douala Cameroun	agriculteur
30	tuekam jules	jules2@gmail.com	$2b$12$z3BtJx44zhJaXmO5uDoMBu8Bimrx55JlmR9Frshh9wYGCVHK3LqU.	699724325	\N	2026-06-22 19:02:40.106386	bandjoun Cameroun	agriculteur
31	madjo talla	madjo@gmail.com	$2b$12$5GXjUZAKVbgYWGCKFVbJ8..cAQz90D4IaIE6/uhBqXO0R5t1V0kZ.	678765432	/api/images/profils/profile_31.jpg	2026-06-23 13:21:42.93515	bandjoun cameroun	agriculteur
32	Admin Principal	admin@tomscan.com	$2b$12$8ns2Qq8wE4e/5bsioJ/WZODXhlEaCjmMsMzrO3j617PYSTfomKXwa	699999999	\N	2026-06-23 13:44:01.204081	Douala, Cameroun	admin
33	Test 21	test21@tomscan.com	$2b$12$OR8DEx5X7xmcXIOe/UaRH.1VyFCg4sL6mnTNORW9r7d6E2J19HSOO	691234567	\N	2026-06-24 08:17:30.220551	Douala	agriculteur
34	sopha	sophora100@gmail.com	$2b$12$t.gv7cWLvbAvEYEuTyE7g.J/BfeThy/6VbzXbAEJ/3rNnyJC3CDnG	56589463	\N	2026-06-25 12:25:04.689558	Yaoundé Cameroun	agriculteur
\.


--
-- Data for Name: zone_infectee; Type: TABLE DATA; Schema: public; Owner: tuekam
--

COPY public.zone_infectee (id_zone, centre_latitude, centre_longitude, rayon, nombre_observations, id_parcelle, zone_type, id_utilisateur) FROM stdin;
66	5.335757699999999	10.434056733333334	1	6	\N	HORS_PARCELLE	31
67	5.354517252272728	10.425597943181819	1	44	\N	HORS_PARCELLE	31
68	5.354517252272728	10.425597943181819	1	44	\N	HORS_PARCELLE	31
70	5.37777005	10.421588700000001	1	8	\N	HORS_PARCELLE	34
65	4.05107	9.76788	1	13	\N	HORS_PARCELLE	33
\.


--
-- Name: conversation_id_conversation_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.conversation_id_conversation_seq', 11, true);


--
-- Name: diagnostic_id_diagnostic_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.diagnostic_id_diagnostic_seq', 1264, true);


--
-- Name: maladie_id_maladie_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.maladie_id_maladie_seq', 6, true);


--
-- Name: message_id_message_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.message_id_message_seq', 83, true);


--
-- Name: notification_id_notification_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.notification_id_notification_seq', 19, true);


--
-- Name: observation_id_observation_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.observation_id_observation_seq', 1328, true);


--
-- Name: parcelle_id_parcelle_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.parcelle_id_parcelle_seq', 48, true);


--
-- Name: session_id_session_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.session_id_session_seq', 29, true);


--
-- Name: utilisateur_id_utilisateur_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.utilisateur_id_utilisateur_seq', 34, true);


--
-- Name: zone_infectee_id_zone_seq; Type: SEQUENCE SET; Schema: public; Owner: tuekam
--

SELECT pg_catalog.setval('public.zone_infectee_id_zone_seq', 70, true);


--
-- Name: conversation conversation_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.conversation
    ADD CONSTRAINT conversation_pkey PRIMARY KEY (id_conversation);


--
-- Name: diagnostic diagnostic_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.diagnostic
    ADD CONSTRAINT diagnostic_pkey PRIMARY KEY (id_diagnostic);


--
-- Name: maladie maladie_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.maladie
    ADD CONSTRAINT maladie_pkey PRIMARY KEY (id_maladie);


--
-- Name: message message_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_pkey PRIMARY KEY (id_message);


--
-- Name: notification notification_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id_notification);


--
-- Name: observation observation_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.observation
    ADD CONSTRAINT observation_pkey PRIMARY KEY (id_observation);


--
-- Name: parcelle parcelle_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.parcelle
    ADD CONSTRAINT parcelle_pkey PRIMARY KEY (id_parcelle);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id_session);


--
-- Name: utilisateur utilisateur_email_key; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.utilisateur
    ADD CONSTRAINT utilisateur_email_key UNIQUE (email);


--
-- Name: utilisateur utilisateur_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.utilisateur
    ADD CONSTRAINT utilisateur_pkey PRIMARY KEY (id_utilisateur);


--
-- Name: zone_infectee zone_infectee_pkey; Type: CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.zone_infectee
    ADD CONSTRAINT zone_infectee_pkey PRIMARY KEY (id_zone);


--
-- Name: idx_notification_parcelle; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_notification_parcelle ON public.notification USING btree (id_parcelle);


--
-- Name: idx_notification_zone; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_notification_zone ON public.notification USING btree (id_zone);


--
-- Name: idx_observation_geog; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_observation_geog ON public.observation USING gist (public.st_setsrid(public.st_makepoint(longitude, latitude), 4326));


--
-- Name: idx_observation_parcelle; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_observation_parcelle ON public.observation USING btree (id_parcelle);


--
-- Name: idx_session_date_debut; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_session_date_debut ON public.session USING btree (date_debut DESC);


--
-- Name: idx_session_utilisateur; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_session_utilisateur ON public.session USING btree (id_utilisateur);


--
-- Name: idx_zone_infectee_parcelle; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_zone_infectee_parcelle ON public.zone_infectee USING btree (id_parcelle);


--
-- Name: idx_zone_infectee_utilisateur; Type: INDEX; Schema: public; Owner: tuekam
--

CREATE INDEX idx_zone_infectee_utilisateur ON public.zone_infectee USING btree (id_utilisateur);


--
-- Name: conversation conversation_id_utilisateur_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.conversation
    ADD CONSTRAINT conversation_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.utilisateur(id_utilisateur) ON DELETE CASCADE;


--
-- Name: diagnostic diagnostic_id_parcelle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.diagnostic
    ADD CONSTRAINT diagnostic_id_parcelle_fkey FOREIGN KEY (id_parcelle) REFERENCES public.parcelle(id_parcelle) ON DELETE SET NULL;


--
-- Name: diagnostic diagnostic_id_utilisateur_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.diagnostic
    ADD CONSTRAINT diagnostic_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.utilisateur(id_utilisateur) ON DELETE CASCADE;


--
-- Name: message message_id_conversation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_id_conversation_fkey FOREIGN KEY (id_conversation) REFERENCES public.conversation(id_conversation) ON DELETE CASCADE;


--
-- Name: notification notification_id_parcelle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_id_parcelle_fkey FOREIGN KEY (id_parcelle) REFERENCES public.parcelle(id_parcelle);


--
-- Name: notification notification_id_utilisateur_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.utilisateur(id_utilisateur) ON DELETE CASCADE;


--
-- Name: notification notification_id_zone_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_id_zone_fkey FOREIGN KEY (id_zone) REFERENCES public.zone_infectee(id_zone);


--
-- Name: observation observation_id_diagnostic_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.observation
    ADD CONSTRAINT observation_id_diagnostic_fkey FOREIGN KEY (id_diagnostic) REFERENCES public.diagnostic(id_diagnostic) ON DELETE CASCADE;


--
-- Name: observation observation_id_maladie_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.observation
    ADD CONSTRAINT observation_id_maladie_fkey FOREIGN KEY (id_maladie) REFERENCES public.maladie(id_maladie);


--
-- Name: observation observation_id_parcelle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.observation
    ADD CONSTRAINT observation_id_parcelle_fkey FOREIGN KEY (id_parcelle) REFERENCES public.parcelle(id_parcelle);


--
-- Name: parcelle parcelle_id_utilisateur_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.parcelle
    ADD CONSTRAINT parcelle_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.utilisateur(id_utilisateur) ON DELETE CASCADE;


--
-- Name: session session_id_utilisateur_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.utilisateur(id_utilisateur);


--
-- Name: zone_infectee zone_infectee_id_parcelle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.zone_infectee
    ADD CONSTRAINT zone_infectee_id_parcelle_fkey FOREIGN KEY (id_parcelle) REFERENCES public.parcelle(id_parcelle);


--
-- Name: zone_infectee zone_infectee_id_utilisateur_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tuekam
--

ALTER TABLE ONLY public.zone_infectee
    ADD CONSTRAINT zone_infectee_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.utilisateur(id_utilisateur) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict yJHYOIq6C50xsVIcvmX9917EkSGPpFdk5DZvakh9z5n2U6PvWRmClKhxqCc7S2g


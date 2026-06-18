// mobile/lib/config.dart
class AppConfig {
  // URL du backend (modifiable sans toucher aux fichiers)
  static const String baseUrl = 'http://192.168.0.176:8000/api';
  static const String baseUrlImages = 'http://192.168.0.176:8000/api/images';

  // Seuils (modifiables ici)
  static const double rayonGroupementM = 1.0;
  static const int seuilCreationZone = 10;
  static const double seuilConfianceYolo = 0.8;

  // Mode temps réel
  static const int fpsCible = 4;
  static const double qualiteImageMin = 20.0;
  static const double rayonDedoublonnageGps = 0.5;

  // Filtres
  static const double gpsPrecisionSeuil = 5.0;
}

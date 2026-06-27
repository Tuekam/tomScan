class AppConfig {
  // URL du backend
  static const String baseUrl = 'http://192.168.158.27:8000/api';
  static const String baseUrlImages = 'http://192.168.158.27:8000/api/images';

  // Seuils (synchro avec backend)
  static const double rayonGroupementM = 3.0;
  static const int seuilCreationZone = 6;

  // Mode temps réel
  static const int fpsCible = 10;
  static const double qualiteImageMin = 15.0; // ← Synchronisé avec backend

  // Filtres GPS
  static const double gpsPrecisionSeuil = 1000.0;
}

// screens/camera_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../config.dart';
import 'result_screen.dart';
import 'map_screen.dart';
import 'realtime_scan_screen.dart';
import 'chatbot_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import '../services/auth_service.dart';
import '../services/local_database_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker();
  final Dio _dio = Dio();
  File? _image;
  String _result = '';
  bool _isLoading = false;

  String _lastDiagnosis = '';
  String _lastConfidence = '';
  String _lastDate = '';
  String _lastLocation = '';
  Map<String, dynamic>? _lastDiagnosticData;

  final LocalDatabaseService _localDb = LocalDatabaseService();

  // Clé pour le stockage du dernier diagnostic (avec user_id)
  String get _lastDiagnosisKey => 'last_diagnosis_${_currentUserId}';
  String get _lastConfidenceKey => 'last_confidence_${_currentUserId}';
  String get _lastDateKey => 'last_date_${_currentUserId}';
  String get _lastLocationKey => 'last_location_${_currentUserId}';
  String get _lastDataKey => 'last_diagnostic_data_${_currentUserId}';

  int _currentUserId = 0;

  // ✅ Nombre de notifications non lues
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
  }

  Future<void> _loadCurrentUserId() async {
    _currentUserId = await AuthService().getUserId() ?? 0;
    if (_currentUserId != 0) {
      _localDb.setUserId(_currentUserId);
    }
    _loadLastDiagnosis();
    _loadUnreadCount();
  }

  // ============================================================
  // ✅ CHARGER LE NOMBRE DE NOTIFICATIONS NON LUES
  // ============================================================
  Future<void> _loadUnreadCount() async {
    try {
      final userId = await AuthService().getUserId() ?? 1;
      final response = await _dio.get(
        '${AppConfig.baseUrl}/notifications/unread/count',
        queryParameters: {'user_id': userId},
      );
      if (response.statusCode == 200) {
        setState(() {
          _unreadCount = response.data['count'] ?? 0;
        });
      }
    } catch (e) {
      print('Erreur chargement notifications: $e');
    }
  }

  // ✅ OUVRIR LES NOTIFICATIONS ET METTRE À JOUR LE BADGE
  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationsScreen(),
      ),
    );
    // Recharger le compteur après fermeture
    await _loadUnreadCount();
  }

  Future<void> _loadLastDiagnosis() async {
    if (_currentUserId == 0) return;

    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _lastDiagnosis = prefs.getString(_lastDiagnosisKey) ?? '';
      _lastConfidence = prefs.getString(_lastConfidenceKey) ?? '';
      _lastDate = prefs.getString(_lastDateKey) ?? '';
      _lastLocation = prefs.getString(_lastLocationKey) ?? '';
    });

    final lastData = prefs.getString(_lastDataKey);
    if (lastData != null) {
      try {
        _lastDiagnosticData =
            Map<String, dynamic>.from(json.decode(lastData) as Map);
      } catch (e) {
        print('Erreur chargement données: $e');
      }
    }
  }

  Future<void> _saveLastDiagnosis({
    required String diagnosis,
    required String confidence,
    required String date,
    required String location,
    required Map<String, dynamic> fullData,
  }) async {
    if (_currentUserId == 0) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastDiagnosisKey, diagnosis);
    await prefs.setString(_lastConfidenceKey, confidence);
    await prefs.setString(_lastDateKey, date);
    await prefs.setString(_lastLocationKey, location);
    await prefs.setString(_lastDataKey, json.encode(fullData));

    setState(() {
      _lastDiagnosis = diagnosis;
      _lastConfidence = confidence;
      _lastDate = date;
      _lastLocation = location;
      _lastDiagnosticData = fullData;
    });
  }

  Future<void> _checkPermissions() async {
    await Permission.camera.request();
    await Permission.location.request();
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Erreur GPS: $e');
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    await _checkPermissions();
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = '';
      });
    }
  }

  String _getLocationName(double lat, double lon) {
    return 'Lat: ${lat.toStringAsFixed(4)}, Lon: ${lon.toStringAsFixed(4)}';
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveDiagnosticLocally({
    required String imagePath,
    required String maladieNom,
    required double confiance,
    required int idDiagnostic,
    required int idObservation,
    required double latitude,
    required double longitude,
    required String description,
    required String symptomes,
    required String recommandation,
    required String niveauGravite,
    required String parcelleNom,
  }) async {
    try {
      final data = {
        'id': idDiagnostic,
        'type': 'photo',
        'maladie_nom': maladieNom,
        'confiance': confiance,
        'image_path': imagePath,
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
        'symptomes': symptomes,
        'recommandation': recommandation,
        'niveau_gravite': niveauGravite,
        'parcelle_nom': parcelleNom,
        'date': DateTime.now().toIso8601String(),
        '_synced': true,
      };

      await _localDb.saveHistoryItem(
        'photo',
        DateTime.now().toIso8601String(),
        data,
      );
      debugPrint('✅ Diagnostic sauvegardé localement (ID: $idDiagnostic)');
    } catch (e) {
      debugPrint('⚠️ Erreur sauvegarde locale: $e');
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null) return;

    setState(() => _isLoading = true);
    _result = '';

    try {
      final position = await _getCurrentLocation();
      final lat = position?.latitude ?? 0.0;
      final lon = position?.longitude ?? 0.0;

      final userId = await AuthService().getUserId() ?? 1;

      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(_image!.path),
        'latitude': lat,
        'longitude': lon,
        'precision_gps': position?.accuracy ?? 5.0,
        'id_utilisateur': userId,
      });

      final response = await _dio.post(
        '${AppConfig.baseUrl}/predict',
        data: formData,
      );

      final data = response.data;
      final maladie = data['maladie']?.toString() ?? 'Inconnue';
      final confiance = data['confiance']?.toDouble() ?? 0.0;

      final locationName = _getLocationName(lat, lon);
      final formattedDate = _getFormattedDate();

      String displayDiagnosis = maladie.replaceAll('_', ' ');
      if (displayDiagnosis.contains('healthy')) displayDiagnosis = 'Sain';
      if (displayDiagnosis.contains('Tomato '))
        displayDiagnosis = displayDiagnosis.replaceAll('Tomato ', '');

      final parcelleNom = data['parcelle_nom'] ?? 'Hors parcelle';
      final idDiagnostic = data['id_diagnostic'] ?? 0;
      final idObservation = data['id_observation'] ?? 0;
      final description = data['description'] ?? '';
      final symptomes = data['symptomes'] ?? '';
      final recommandation = data['recommandation'] ?? '';
      final niveauGravite = data['niveau_gravite'] ?? '';

      final fullData = {
        'imagePath': _image!.path,
        'maladie': maladie,
        'confiance': confiance,
        'id_diagnostic': idDiagnostic,
        'id_observation': idObservation,
        'latitude': lat,
        'longitude': lon,
        'description': description,
        'symptomes': symptomes,
        'recommandation': recommandation,
        'niveau_gravite': niveauGravite,
        'parcelle_nom': parcelleNom,
      };

      await _saveDiagnosticLocally(
        imagePath: _image!.path,
        maladieNom: maladie,
        confiance: confiance,
        idDiagnostic: idDiagnostic,
        idObservation: idObservation,
        latitude: lat,
        longitude: lon,
        description: description,
        symptomes: symptomes,
        recommandation: recommandation,
        niveauGravite: niveauGravite,
        parcelleNom: parcelleNom,
      );

      await _saveLastDiagnosis(
        diagnosis: displayDiagnosis,
        confidence: confiance.toString(),
        date: formattedDate,
        location: locationName,
        fullData: fullData,
      );

      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            imagePath: _image!.path,
            maladie: maladie,
            confiance: confiance,
            idDiagnostic: idDiagnostic,
            idObservation: idObservation,
            latitude: lat,
            longitude: lon,
            description: description,
            symptomes: symptomes,
            recommandation: recommandation,
            niveauGravite: niveauGravite,
          ),
        ),
      );

      if (result != null && mounted) {
        if (result['action'] == 'view_on_map') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MapScreen(
                initialLatitude: result['latitude'],
                initialLongitude: result['longitude'],
                highlightDiagnosticId: result['id_diagnostic'],
                highlightMaladie: result['maladie'],
                highlightConfiance: result['confiance'],
              ),
            ),
          );
        } else if (result['action'] == 'ask_chatbot') {
          final question = result['question'] ?? '';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatbotScreen(initialQuestion: question),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _result = 'Erreur: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openLastDiagnostic() async {
    if (_lastDiagnosticData == null) return;

    final data = _lastDiagnosticData!;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(
          imagePath: data['imagePath'] ?? '',
          maladie: data['maladie'] ?? 'Inconnue',
          confiance: (data['confiance'] ?? 0.0).toDouble(),
          idDiagnostic: data['id_diagnostic'] ?? 0,
          idObservation: data['id_observation'] ?? 0,
          latitude: data['latitude'] ?? 0.0,
          longitude: data['longitude'] ?? 0.0,
          description: data['description'] ?? '',
          symptomes: data['symptomes'] ?? '',
          recommandation: data['recommandation'] ?? '',
          niveauGravite: data['niveau_gravite'] ?? '',
        ),
      ),
    );

    if (result != null && mounted) {
      if (result['action'] == 'view_on_map') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MapScreen(
              initialLatitude: result['latitude'],
              initialLongitude: result['longitude'],
              highlightDiagnosticId: result['id_diagnostic'],
              highlightMaladie: result['maladie'],
              highlightConfiance: result['confiance'],
            ),
          ),
        );
      } else if (result['action'] == 'ask_chatbot') {
        final question = result['question'] ?? '';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatbotScreen(initialQuestion: question),
          ),
        );
      }
    }
  }

  Future<void> _startRealtimeScan() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission caméra refusée'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RealtimeScanScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.eco, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Text(
              'TomScan',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          // ✅ BOUTON NOTIFICATIONS AVEC BADGE
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: _openNotifications,
                color: AppTheme.primary,
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
            color: AppTheme.primary,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(_image!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 48, color: AppTheme.primary),
                        const SizedBox(height: 8),
                        Text('Prêt à scanner',
                            style: TextStyle(color: AppTheme.primary)),
                        const SizedBox(height: 4),
                        Text(
                          'Cadrez une feuille de tomate',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMedium),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed:
                  _isLoading ? null : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Prendre une photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _isLoading ? null : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.image),
              label: const Text('Choisir dans la galerie'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primaryLight),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _startRealtimeScan,
              icon: const Icon(Icons.videocam),
              label: const Text('Mode temps réel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primaryLight),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            if (_image != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _analyzeImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Analyser'),
                ),
              ),
            if (_lastDiagnosis.isNotEmpty)
              GestureDetector(
                onTap: _openLastDiagnostic,
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 18, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            const Text('Dernier diagnostic',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Icon(Icons.chevron_right,
                                size: 18, color: Colors.grey),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_lastDiagnosis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                Text(_lastDate,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('$_lastConfidence%',
                                  style: TextStyle(color: AppTheme.primary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(_lastLocation,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_result.isNotEmpty && _result.startsWith('Erreur'))
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text('Erreur',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(_result, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

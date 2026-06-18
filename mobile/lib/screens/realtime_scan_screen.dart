// screens/realtime_scan_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';
import 'realtime_result_screen.dart';

enum GpsStatus { waiting, ready, error }

class RealtimeScanScreen extends StatefulWidget {
  const RealtimeScanScreen({super.key});

  @override
  State<RealtimeScanScreen> createState() => _RealtimeScanScreenState();
}

class _RealtimeScanScreenState extends State<RealtimeScanScreen> {
  final Dio _dio = Dio();

  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isScanning = false;
  String _sessionId = '';

  int _totalFrames = 0;
  int _analyzedFrames = 0;
  int _ignoredFrames = 0;
  Map<String, int> _maladiesCount = {};
  List<Detection> _detections = [];

  Timer? _frameTimer;
  Timer? _statusTimer;
  DateTime? _startTime;

  // GPS Status
  GpsStatus _gpsStatus = GpsStatus.waiting;
  double _gpsAccuracy = 0.0;
  bool _isWaitingGps = true;

  final int _fps = 4;
  final Duration _frameInterval = Duration(milliseconds: 250);

  // Base URL
  final String _baseUrl = 'http://192.168.0.176:8000/api';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _statusTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucune caméra disponible'),
              backgroundColor: Colors.red),
        );
        return;
      }

      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      await _cameraController!.startImageStream((image) {
        // Le flux d'images est géré via le timer
      });

      setState(() {
        _isInitialized = true;
      });

      // Démarrer automatiquement l'attente GPS
      _waitForGpsFix();
    } catch (e) {
      print('Erreur caméra: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erreur caméra: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ============================================================
  // GPS : Attendre une précision stable
  // ============================================================
  Future<void> _waitForGpsFix() async {
    setState(() {
      _isWaitingGps = true;
      _gpsStatus = GpsStatus.waiting;
      _gpsAccuracy = 0.0;
    });

    int attempts = 0;
    const maxAttempts = 30; // 30 * 2s = 60 secondes max

    while (attempts < maxAttempts && _isWaitingGps) {
      attempts++;

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );

        _gpsAccuracy = position.accuracy;

        print('📍 GPS: précision=${position.accuracy.toStringAsFixed(1)}m, ' +
            'source=${position.isMocked ? "mock" : "satellite"}');

        // 🔥 Seuil : accepter si précision ≤ 10 mètres
        if (position.accuracy <= 5.0) {
          setState(() {
            _gpsStatus = GpsStatus.ready;
            _gpsAccuracy = position.accuracy;
            _isWaitingGps = false;
          });
          return;
        }

        // Mettre à jour l'UI
        setState(() {});
      } catch (e) {
        print('Erreur GPS: $e');
      }

      // Attendre 2 secondes avant de réessayer
      await Future.delayed(const Duration(seconds: 2));
    }

    // Timeout : GPS non stabilisé
    setState(() {
      _gpsStatus = GpsStatus.error;
      _isWaitingGps = false;
    });
  }

  // ============================================================
  // Démarrer le scan
  // ============================================================
  Future<void> _startScan() async {
    // Vérifier les permissions
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

    // 🔥 Vérifier que le GPS est prêt
    if (_gpsStatus != GpsStatus.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS non prêt. Veuillez attendre la stabilisation.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _totalFrames = 0;
      _analyzedFrames = 0;
      _ignoredFrames = 0;
      _maladiesCount = {};
      _detections = [];
      _startTime = DateTime.now();
    });

    try {
      final startRes = await _dio.post('$_baseUrl/realtime/start');
      _sessionId = startRes.data['session_id'];
      print('🎬 Session temps réel démarrée: $_sessionId');

      _frameTimer = Timer.periodic(_frameInterval, (timer) async {
        await _captureAndSendFrame();
      });

      _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        await _updateStatus();
      });
    } catch (e) {
      print('Erreur démarrage scan: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isScanning = false);
    }
  }

  // ============================================================
  // Capturer et envoyer une frame
  // ============================================================
  Future<void> _captureAndSendFrame() async {
    if (!_isInitialized || _cameraController == null || !_isScanning) return;

    try {
      final image = await _cameraController!.takePicture();
      _totalFrames++;

      final position = await _getCurrentLocation();
      final lat = position?.latitude ?? 0.0;
      final lon = position?.longitude ?? 0.0;
      final accuracy = position?.accuracy ?? 5.0;

      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(image.path),
        'latitude': lat,
        'longitude': lon,
        'precision_gps': accuracy,
      });

      final response = await _dio.post(
        '$_baseUrl/realtime/$_sessionId/frame',
        data: formData,
      );

      final data = response.data;

      if (data['status'] == 'analyzed') {
        _analyzedFrames++;
        final maladie = data['maladie'] ?? 'Inconnue';
        _maladiesCount[maladie] = (_maladiesCount[maladie] ?? 0) + 1;

        // Mettre à jour les détections
        if (data['detections'] != null) {
          final detections = (data['detections'] as List)
              .map((d) => Detection(
                    maladie: d['maladie'] ?? 'Inconnue',
                    confiance: (d['confiance'] ?? 0).toDouble(),
                    x: d['x'] ?? 0,
                    y: d['y'] ?? 0,
                    width: d['width'] ?? 0,
                    height: d['height'] ?? 0,
                    bboxColor: d['bbox_color'] ?? '#6B7280',
                  ))
              .toList();
          setState(() {
            _detections = detections;
          });
        }
      } else {
        _ignoredFrames++;
      }

      // Mise à jour de l'UI
      if (mounted) {
        setState(() {});
      }

      // Supprimer le fichier temporaire
      await File(image.path).delete();
    } catch (e) {
      print('Erreur capture frame: $e');
    }
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateStatus() async {
    if (_sessionId.isEmpty) return;
    try {
      final response = await _dio.get('$_baseUrl/realtime/$_sessionId/status');
      final data = response.data;
      setState(() {
        _totalFrames = data['total_frames'] ?? _totalFrames;
        _analyzedFrames = data['frames_analysees'] ?? _analyzedFrames;
      });
    } catch (e) {
      print('Erreur status: $e');
    }
  }

  Future<void> _stopScan() async {
    _frameTimer?.cancel();
    _statusTimer?.cancel();
    setState(() => _isScanning = false);

    try {
      final response = await _dio.post('$_baseUrl/realtime/$_sessionId/end');
      final data = response.data;
      if (data['status'] == 'completed' && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RealtimeResultScreen(
              resume: data['resume'],
              zones: List<Map<String, dynamic>>.from(data['zones_crees'] ?? []),
            ),
          ),
        );
      }
    } catch (e) {
      print('Erreur arrêt: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erreur arrêt: $e'), backgroundColor: Colors.red),
      );
      Navigator.pop(context);
    }
  }

  Color _getBboxColor(String colorHex) {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return AppTheme.primary;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mode temps réel'),
        backgroundColor: _isScanning ? AppTheme.danger : AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopScan,
              tooltip: 'Arrêter le scan',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Cas 1 : Caméra non initialisée
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initialisation de la caméra...'),
          ],
        ),
      );
    }

    // Cas 2 : Attente GPS
    if (_isWaitingGps) {
      return _buildGpsWaitingScreen();
    }

    // Cas 3 : GPS en erreur
    if (_gpsStatus == GpsStatus.error) {
      return _buildGpsErrorScreen();
    }

    // Cas 4 : Scan en cours ou prêt
    return _buildScanScreen();
  }

  Widget _buildGpsWaitingScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.gps_fixed,
              size: 64,
              color: _gpsAccuracy <= 5 ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 24),
            const Text(
              'Acquisition du signal GPS...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Précision: ${_gpsAccuracy.toStringAsFixed(1)} m',
              style: TextStyle(
                fontSize: 14,
                color: _gpsAccuracy <= 5 ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _gpsAccuracy <= 20
                  ? '✅ Signal suffisant'
                  : '⏳ Attendez la stabilisation...',
              style: TextStyle(
                fontSize: 13,
                color: _gpsAccuracy <= 5 ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Positionnement GPS en cours...',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_off, size: 64, color: AppTheme.danger),
            const SizedBox(height: 24),
            const Text(
              'GPS non disponible',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Précision: ${_gpsAccuracy.toStringAsFixed(1)} m',
              style: TextStyle(color: AppTheme.danger),
            ),
            const SizedBox(height: 8),
            const Text(
              'Assurez-vous d\'être en extérieur avec une vue dégagée sur le ciel.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isWaitingGps = true;
                  _gpsStatus = GpsStatus.waiting;
                });
                _waitForGpsFix();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanScreen() {
    return Column(
      children: [
        // Vue caméra avec bounding boxes
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              CameraPreview(_cameraController!),
              // Bounding boxes
              if (_detections.isNotEmpty)
                ..._detections.map((detection) {
                  final size = MediaQuery.of(context).size;
                  final previewWidth = size.width;
                  final previewHeight = size.height * 0.6;

                  return Positioned(
                    left: detection.x * previewWidth / 640,
                    top: detection.y * previewHeight / 480,
                    width: detection.width * previewWidth / 640,
                    height: detection.height * previewHeight / 480,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _getBboxColor(detection.bboxColor),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          color: _getBboxColor(detection.bboxColor),
                          child: Text(
                            '${detection.maladie} ${detection.confiance.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              // Indicateur de scan
              if (_isScanning)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record,
                            color: Colors.red, size: 10),
                        SizedBox(width: 8),
                        Text(
                          'LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              // GPS précis
              if (_gpsAccuracy > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gps_fixed, color: Colors.green, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${_gpsAccuracy.toStringAsFixed(1)}m',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Barre d'information
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(Icons.camera_alt, 'Total', '$_totalFrames'),
              _buildStatItem(
                  Icons.check_circle, 'Analysées', '$_analyzedFrames'),
              _buildStatItem(Icons.block, 'Ignorées', '$_ignoredFrames'),
              _buildStatItem(
                  Icons.timer,
                  'Temps',
                  _startTime != null
                      ? _formatDuration(DateTime.now().difference(_startTime!))
                      : '00:00'),
            ],
          ),
        ),

        // Maladies détectées
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.grey.shade50,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _maladiesCount.entries.map((entry) {
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${entry.key}: ${entry.value}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Bouton Démarrer/Arrêter
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanning ? _stopScan : _startScan,
              icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
              label: Text(_isScanning ? 'Arrêter le scan' : 'Démarrer le scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isScanning ? AppTheme.danger : AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.primary),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

// ============================================================
// Modèle Detection
// ============================================================
class Detection {
  final String maladie;
  final double confiance;
  final int x;
  final int y;
  final int width;
  final int height;
  final String bboxColor;

  Detection({
    required this.maladie,
    required this.confiance,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.bboxColor,
  });
}

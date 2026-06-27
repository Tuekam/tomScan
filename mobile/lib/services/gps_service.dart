import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  Position? _currentPosition;
  double _currentAccuracy = 0.0;
  bool _isListening = false;
  Timer? _gpsTimer;
  final List<void Function(Position)> _listeners = [];

  // 🔥 Sauvegarde de la dernière position
  static const String _lastPositionKey = 'last_gps_position';

  // Position par défaut (Douala)
  static const double _defaultLat = 4.051070;
  static const double _defaultLon = 9.767880;

  // 🔥 Dernière position valide (fallback)
  Position? _lastValidPosition;

  // ============================================================
  // SAUVEGARDE ET CHARGEMENT DE LA DERNIÈRE POSITION
  // ============================================================
  Future<void> _saveLastPosition(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = json.encode({
        'lat': position.latitude,
        'lon': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString(_lastPositionKey, data);
      _lastValidPosition = position;
      debugPrint(
          '💾 Position sauvegardée: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('❌ Erreur sauvegarde position: $e');
    }
  }

  Future<Position?> _loadLastPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_lastPositionKey);
      if (data != null) {
        final map = json.decode(data) as Map<String, dynamic>;
        final lat = map['lat'] as double;
        final lon = map['lon'] as double;
        final accuracy = map['accuracy'] as double? ?? 5.0;

        // Créer un objet Position à partir des données sauvegardées
        final position = Position(
          latitude: lat,
          longitude: lon,
          accuracy: accuracy,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          timestamp: DateTime.now(),
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
        return position;
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement position: $e');
    }
    return null;
  }

  // ============================================================
  // DÉMARRAGE DU SERVICE GPS
  // ============================================================
  Future<void> startGpsService() async {
    if (_isListening) return;

    // 🔥 1. Charger la dernière position sauvegardée immédiatement
    final savedPosition = await _loadLastPosition();
    if (savedPosition != null) {
      _currentPosition = savedPosition;
      _lastValidPosition = savedPosition;
      _notifyListeners(savedPosition);
      debugPrint(
          '📍 Position chargée depuis le cache: ${savedPosition.latitude}, ${savedPosition.longitude}');
    }

    // 2. Vérifier les permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // 3. Vérifier si le GPS est activé
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    _isListening = true;

    // 4. Configuration moderne pour geolocator
    final settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      timeLimit: const Duration(seconds: 30),
    );

    // 5. 🔥 Stream de position (plus fiable que le timer)
    Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((Position position) {
      _currentPosition = position;
      _currentAccuracy = position.accuracy;
      _lastValidPosition = position;
      _notifyListeners(position);

      // 🔥 Sauvegarder automatiquement
      _saveLastPosition(position);

      debugPrint(
          '📍 Position GPS mise à jour: ${position.latitude}, ${position.longitude} (précision: ${position.accuracy}m)');
    });

    // 6. 🔥 TIMER AMÉLIORÉ : Ne mettre à jour que si la précision est meilleure
    _gpsTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 5),
          ),
        );

        // 🔥 Ne mettre à jour que si la nouvelle position est plus précise
        if (_currentPosition == null || position.accuracy < _currentAccuracy) {
          _currentPosition = position;
          _currentAccuracy = position.accuracy;
          _lastValidPosition = position;
          _notifyListeners(position);
          _saveLastPosition(position);
          debugPrint(
              '📍 Position améliorée: ${position.latitude}, ${position.longitude} (précision: ${position.accuracy}m)');
        }
      } catch (e) {
        // ignore
      }
    });

    debugPrint('📍 Service GPS démarré');
  }

  // ============================================================
  // MÉTHODES PUBLIQUES
  // ============================================================

  void addListener(void Function(Position) listener) {
    _listeners.add(listener);
    // 🔥 Notifier immédiatement avec la position actuelle si disponible
    if (_currentPosition != null) {
      listener(_currentPosition!);
    }
  }

  void removeListener(void Function(Position) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners(Position position) {
    for (var listener in _listeners) {
      listener(position);
    }
  }

  // ============================================================
  // POSITION PAR DÉFAUT (FALLBACK)
  // ============================================================
  Position get defaultPosition {
    return Position(
      latitude: _defaultLat,
      longitude: _defaultLon,
      accuracy: 50.0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      timestamp: DateTime.now(),
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  // 🔥 Position actuelle ou fallback
  Position get currentPositionOrFallback {
    if (_currentPosition != null) {
      return _currentPosition!;
    }
    if (_lastValidPosition != null) {
      return _lastValidPosition!;
    }
    return defaultPosition;
  }

  Position? get currentPosition => _currentPosition;
  double get currentAccuracy => _currentAccuracy;

  bool get isGpsReady {
    return _currentPosition != null && _currentAccuracy < 20.0;
  }

  // 🔥 Avoir une position valide (même avec faible précision)
  bool get hasPosition {
    return _currentPosition != null || _lastValidPosition != null;
  }

  void dispose() {
    _gpsTimer?.cancel();
    _isListening = false;
    _listeners.clear();
  }
}

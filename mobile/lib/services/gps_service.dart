// mobile/lib/services/gps_service.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  Position? _currentPosition;
  double _currentAccuracy = 0.0;
  bool _isListening = false;
  Timer? _gpsTimer;
  final List<void Function(Position)> _listeners = [];

  // Démarrer le service GPS (à appeler une fois au lancement)
  Future<void> startGpsService() async {
    if (_isListening) return;

    // Vérifier les permissions
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

    // Vérifier si le GPS est activé
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    _isListening = true;

    // Configuration moderne pour geolocator
    final settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      timeLimit: const Duration(seconds: 30),
    );

    // Écouter les changements de position en continu
    Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((Position position) {
      _currentPosition = position;
      _currentAccuracy = position.accuracy;
      _notifyListeners(position);
    });

    // Timer de rafraîchissement (toutes les 5 secondes)
    _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 5),
          ),
        );
        _currentPosition = position;
        _currentAccuracy = position.accuracy;
        _notifyListeners(position);
      } catch (e) {
        // ignore
      }
    });

    debugPrint('📍 Service GPS démarré');
  }

  void addListener(void Function(Position) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(Position) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners(Position position) {
    for (var listener in _listeners) {
      listener(position);
    }
  }

  Position? get currentPosition => _currentPosition;
  double get currentAccuracy => _currentAccuracy;
  bool get isGpsReady => _currentPosition != null && _currentAccuracy < 20.0;

  void dispose() {
    _gpsTimer?.cancel();
    _isListening = false;
    _listeners.clear();
  }
}

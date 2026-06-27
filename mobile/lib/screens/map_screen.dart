import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';

class MapScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final int? highlightDiagnosticId;
  final int? highlightZoneId;
  final String? highlightMaladie;
  final double? highlightConfiance;

  const MapScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.highlightDiagnosticId,
    this.highlightZoneId,
    this.highlightMaladie,
    this.highlightConfiance,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final Dio _dio = Dio();

  late MapController _mapController;
  final List<Marker> _zoneMarkers = [];
  List<ZoneData> _zones = [];
  bool _isLoadingData = true;
  String? _errorMessage;
  bool _isLocating = false;

  late AnimationController _animationController;

  LatLng? _userPosition;
  Marker? _userMarker;
  Marker? _highlightMarker;

  late LatLng _initialCenter;
  late double _initialZoom;

  bool _isSatellite = true;
  bool _isDrawingParcel = false;
  List<LatLng> _parcelPoints = [];
  List<Polygon> _parcelPolygons = [];
  List<Marker> _parcelMarkers = [];
  final List<Map<String, dynamic>> _userParcels = [];

  static const LatLng _defaultCenter = LatLng(4.051070, 9.767880);

  int _userId = 1;

  static const String _lastPositionKey = 'last_gps_position';

  @override
  void initState() {
    super.initState();

    _initialCenter =
        (widget.initialLatitude != null && widget.initialLongitude != null)
            ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
            : _defaultCenter;
    _initialZoom = (widget.initialLatitude != null) ? 18 : 13;

    _mapController = MapController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _getLastPosition().then((lastPos) {
      if (lastPos != null && mounted) {
        print(
            '📍 Chargement de la dernière position: ${lastPos.latitude}, ${lastPos.longitude}');
        setState(() {
          _initialCenter = lastPos;
          _initialZoom = 16;
          _userPosition = lastPos;
          _userMarker = _buildUserMarker(lastPos);
        });
        _mapController.move(lastPos, 16);
      }
    });

    if (widget.highlightZoneId != null) {
      _highlightMarker = Marker(
        point: _initialCenter,
        width: 80,
        height: 80,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.location_on, color: Colors.blue, size: 30),
          ),
        ),
      );
    }

    _loadUserId();
  }

  Future<void> _loadUserId() async {
    _userId = await AuthService().getUserId() ?? 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ============================================================
  // SAUVEGARDE ET CHARGEMENT DE LA DERNIÈRE POSITION
  // ============================================================
  Future<void> _saveLastPosition(double lat, double lon) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = json.encode({'lat': lat, 'lon': lon});
      await prefs.setString(_lastPositionKey, data);
      print('💾 Dernière position sauvegardée: $lat, $lon');
    } catch (e) {
      print('❌ Erreur sauvegarde position: $e');
    }
  }

  Future<LatLng?> _getLastPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_lastPositionKey);
      if (data != null) {
        final map = json.decode(data) as Map<String, dynamic>;
        return LatLng(map['lat'] as double, map['lon'] as double);
      }
    } catch (e) {
      print('❌ Erreur chargement position: $e');
    }
    return null;
  }

  // ============================================================
  // CHARGEMENT DES DONNÉES
  // ============================================================
  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    await Future.wait([
      _loadZones(),
      _loadUserParcels(),
    ]);

    await _getUserLocation();

    if (_userPosition != null && mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _mapController.move(_userPosition!, 17);
        print(
            '📍 Carte FORCÉE sur position: ${_userPosition!.latitude}, ${_userPosition!.longitude}');
      });
    }

    setState(() {
      _isLoadingData = false;
    });

    if (widget.highlightZoneId != null) {
      final zone = _zones.firstWhere(
        (z) => z.id == widget.highlightZoneId,
        orElse: () => ZoneData(
          id: -1,
          latitude: 0.0,
          longitude: 0.0,
          rayon: 0.0,
          nombreObservations: 0,
          couleur: 'orange',
          zoneType: 'HORS_PARCELLE',
          parcelleNom: null,
          popupText: '',
        ),
      );
      if (zone.id != -1) {
        Future.delayed(const Duration(milliseconds: 600), () {
          _mapController.move(
            LatLng(zone.latitude, zone.longitude),
            18,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '📍 Zone #${zone.id} - ${zone.zoneType == "DANS_PARCELLE" ? "Dans parcelle" : "Hors parcelle"}',
                ),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
      }
    }
  }

  // ============================================================
  // GPS
  // ============================================================
  Future<void> _getUserLocation() async {
    setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final lastPos = await _getLastPosition();
        if (lastPos != null) {
          setState(() {
            _userPosition = lastPos;
            _userMarker = _buildUserMarker(lastPos);
            _errorMessage =
                '📍 Position basée sur la dernière localisation connue';
            _isLocating = false;
          });
          if (widget.initialLatitude == null && mounted) {
            _mapController.move(lastPos, 16);
          }
          return;
        }

        setState(() {
          _errorMessage = '📍 GPS désactivé. Activez-le dans les paramètres.';
          _isLocating = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          final lastPos = await _getLastPosition();
          if (lastPos != null) {
            setState(() {
              _userPosition = lastPos;
              _userMarker = _buildUserMarker(lastPos);
              _errorMessage =
                  '📍 Position basée sur la dernière localisation connue';
              _isLocating = false;
            });
            if (widget.initialLatitude == null && mounted) {
              _mapController.move(lastPos, 16);
            }
            return;
          }
          setState(() {
            _errorMessage = 'Permission de localisation refusée';
            _isLocating = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        final lastPos = await _getLastPosition();
        if (lastPos != null) {
          setState(() {
            _userPosition = lastPos;
            _userMarker = _buildUserMarker(lastPos);
            _errorMessage =
                '📍 Position basée sur la dernière localisation connue';
            _isLocating = false;
          });
          if (widget.initialLatitude == null && mounted) {
            _mapController.move(lastPos, 16);
          }
          return;
        }
        setState(() {
          _errorMessage = 'Permission de localisation refusée définitivement';
          _isLocating = false;
        });
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 30),
      );

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      final userLatLng = LatLng(position.latitude, position.longitude);
      print('📍 Position GPS: ${position.latitude}, ${position.longitude}');

      await _saveLastPosition(position.latitude, position.longitude);

      setState(() {
        _userPosition = userLatLng;
        _userMarker = _buildUserMarker(userLatLng);
        _errorMessage = null;
        _isLocating = false;
        _initialCenter = userLatLng;
        _initialZoom = 17;
      });

      if (mounted) {
        _mapController.move(userLatLng, 17);
        print(
            '📍 Carte centrée sur position GPS: ${position.latitude}, ${position.longitude}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '📍 Position trouvée (précision: ${position.accuracy.toStringAsFixed(1)}m)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('❌ Erreur GPS: $e');

      final lastPos = await _getLastPosition();
      if (lastPos != null) {
        setState(() {
          _userPosition = lastPos;
          _userMarker = _buildUserMarker(lastPos);
          _errorMessage =
              '📍 Position basée sur la dernière localisation connue';
          _isLocating = false;
        });
        if (widget.initialLatitude == null && mounted) {
          _mapController.move(lastPos, 16);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('📍 Utilisation de la dernière position connue'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      setState(() {
        _errorMessage =
            'Impossible d\'obtenir votre position. Vérifiez le GPS.';
        _isLocating = false;
      });
    }
  }

  Marker _buildUserMarker(LatLng position) {
    return Marker(
      point: position,
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.blue, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(Icons.my_location, color: Colors.blue, size: 16),
      ),
    );
  }

  // ============================================================
  // CHARGEMENT DES ZONES
  // ============================================================
  Future<void> _loadZones() async {
    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/zones',
        queryParameters: {'user_id': _userId},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final features = data['features'] as List? ?? [];

        final List<ZoneData> zones = [];
        final List<Marker> markers = [];

        for (var feature in features) {
          final geometry = feature['geometry'];
          final properties = feature['properties'];

          if (geometry != null && properties != null) {
            final coordinates = geometry['coordinates'] as List?;
            if (coordinates != null && coordinates.length >= 2) {
              final lon = coordinates[0] as double;
              final lat = coordinates[1] as double;
              final id = properties['id'] as int? ?? 0;
              final rayon = properties['rayon'] as double? ?? 3.0;
              final nombreObs = properties['nombre_observations'] as int? ?? 0;
              final couleur = properties['couleur'] as String? ?? 'orange';
              final zoneType =
                  properties['zone_type'] as String? ?? 'HORS_PARCELLE';
              final parcelleNom = properties['parcelle_nom'] as String?;
              final popupText =
                  properties['popup_text'] as String? ?? 'Zone #$id';

              final zone = ZoneData(
                id: id,
                latitude: lat,
                longitude: lon,
                rayon: rayon,
                nombreObservations: nombreObs,
                couleur: couleur,
                zoneType: zoneType,
                parcelleNom: parcelleNom,
                popupText: popupText,
              );
              zones.add(zone);

              markers.add(
                Marker(
                  point: LatLng(lat, lon),
                  width: _getMarkerSize(nombreObs, zoneType),
                  height: _getMarkerSize(nombreObs, zoneType),
                  child: _buildZoneMarker(zone),
                ),
              );
            }
          }
        }

        setState(() {
          _zones = zones;
          _zoneMarkers.clear();
          _zoneMarkers.addAll(markers);
        });

        if (widget.initialLatitude != null && widget.initialLongitude != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _mapController.move(
              LatLng(widget.initialLatitude!, widget.initialLongitude!),
              18,
            );
            if (widget.highlightMaladie != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '📍 Diagnostic #${widget.highlightDiagnosticId}: ${widget.highlightMaladie!.replaceAll('_', ' ')}'),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur chargement des zones: $e';
      });
    }
  }

  // ============================================================
  // CHARGEMENT DES PARCELLES
  // ============================================================
  Future<void> _loadUserParcels() async {
    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/parcelles?id_utilisateur=$_userId',
      );

      if (response.statusCode == 200) {
        final parcels = response.data as List;
        _userParcels.clear();
        _parcelPolygons.clear();
        _parcelMarkers.clear();

        for (var parcel in parcels) {
          final pointsList = parcel['points'] as List;
          final points =
              pointsList.map<LatLng>((p) => LatLng(p[0], p[1])).toList();

          final surfaceHa = parcel['surface_ha']?.toDouble() ?? 0.0;
          final nom = parcel['nom'] ?? 'Parcelle';
          final id = parcel['id'];

          _addParcelToMap(id, nom, points, surfaceHa);
        }
        setState(() {});
      }
    } catch (e) {
      debugPrint('Erreur chargement parcelles: $e');
    }
  }

  void _addParcelToMap(
      int id, String nom, List<LatLng> points, double surfaceHa) {
    _userParcels.add({
      'id': id,
      'nom': nom,
      'points': points,
      'surface_ha': surfaceHa,
    });

    _parcelPolygons.add(
      Polygon(
        points: points,
        color: Colors.red.withValues(alpha: 0.15),
        borderColor: Colors.red,
        borderStrokeWidth: 2,
        isDotted: true,
      ),
    );

    final centerLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final centerLon =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;

    _parcelMarkers.add(
      Marker(
        point: LatLng(centerLat, centerLon),
        width: 150,
        height: 30,
        child: GestureDetector(
          onTap: () => _showParcelDetails(id, nom, points.length, surfaceHa),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: nom,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.9),
                          blurRadius: 3,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                  ),
                  TextSpan(
                    text: ' ${surfaceHa.toStringAsFixed(2)}ha',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.9),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MARQUEURS
  // ============================================================
  double _getMarkerSize(int nombreObs, String zoneType) {
    if (zoneType == 'HORS_PARCELLE') return 36;
    if (nombreObs >= 20) return 48;
    if (nombreObs >= 10) return 40;
    return 32;
  }

  Widget _buildZoneMarker(ZoneData zone) {
    Color markerColor;
    double opacity;
    double borderWidth;

    if (zone.zoneType == "DANS_PARCELLE") {
      if (zone.couleur == 'red') {
        markerColor = Colors.red;
      } else if (zone.couleur == 'orange') {
        markerColor = Colors.orange;
      } else {
        markerColor = Colors.amber;
      }
      opacity = 1.0;
      borderWidth = 3.0;
    } else if (zone.zoneType == "HORS_PARCELLE") {
      markerColor = Colors.orange;
      opacity = 0.55;
      borderWidth = 2.0;
    } else {
      markerColor = Colors.red.shade900;
      opacity = 0.85;
      borderWidth = 2.5;
    }

    return GestureDetector(
      onTap: () => _showZoneDetails(zone),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 300),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                color: markerColor.withValues(alpha: opacity),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: markerColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
                border: Border.all(color: Colors.white, width: borderWidth),
              ),
              child: Center(
                child: Text(
                  '${zone.nombreObservations}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // CENTRAGE SUR L'UTILISATEUR
  // ============================================================
  Future<void> _centerOnUser() async {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 17);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Centrage sur votre position'),
          duration: Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      await _getUserLocation();
      if (_userPosition != null && mounted) {
        _mapController.move(_userPosition!, 17);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'obtenir votre position'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ============================================================
  // DESSIN DE PARCELLES
  // ============================================================
  void _startDrawingParcel() {
    setState(() {
      _isDrawingParcel = true;
      _parcelPoints.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliquez sur la carte pour ajouter des points'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _addPointToParcel(LatLng point) {
    if (!_isDrawingParcel) return;
    setState(() {
      _parcelPoints.add(point);
    });
  }

  Future<void> _saveParcel() async {
    if (_parcelPoints.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Une parcelle doit avoir au moins 3 points'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final parcelName = await _showNameDialog();
    if (parcelName == null || parcelName.isEmpty) return;

    setState(() => _isLoadingData = true);

    try {
      final pointsForApi =
          _parcelPoints.map((p) => [p.latitude, p.longitude]).toList();

      final response = await _dio.post(
        '${AppConfig.baseUrl}/parcelles',
        data: {
          'nom': parcelName,
          'points': pointsForApi,
          'id_utilisateur': _userId
        },
      );

      if (response.statusCode == 200) {
        await _loadUserParcels();
        await _loadZones();
        setState(() {
          _isDrawingParcel = false;
          _parcelPoints.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Parcelle "$parcelName" créée !'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom de la parcelle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Ex: Parcelle Nord'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _cancelDrawing() {
    setState(() {
      _isDrawingParcel = false;
      _parcelPoints.clear();
    });
  }

  // ============================================================
  // SUPPRESSION PARCELLE
  // ============================================================
  Future<void> _deleteParcel(int id, String nom) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Supprimer la parcelle'),
          content: Text('Voulez-vous vraiment supprimer la parcelle "$nom" ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Non')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Oui')),
          ],
        );
      },
    );
    if (confirm != true) return;

    try {
      final userId = await AuthService().getUserId() ?? 1;

      await _dio.delete(
        '${AppConfig.baseUrl}/parcelles/$id',
        queryParameters: {'user_id': userId},
      );

      await _loadUserParcels();
      await _loadZones();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parcelle supprimée'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showParcelDetails(
      int id, String nom, int pointsCount, double surfaceHa) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.agriculture, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(nom,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold))),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow(Icons.map, 'Points', '$pointsCount points'),
              _buildDetailRow(Icons.square_foot, 'Surface',
                  '${surfaceHa.toStringAsFixed(2)} hectares'),
              _buildDetailRow(Icons.landscape, 'Surface (m²)',
                  '${(surfaceHa * 10000).toStringAsFixed(0)} m²'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteParcel(id, nom),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Supprimer',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.red.shade300)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _centerOnParcel(id);
                      },
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Centrer'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _centerOnParcel(int id) {
    final parcel = _userParcels.firstWhere((p) => p['id'] == id);
    final points = parcel['points'] as List<LatLng>;
    final centerLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final centerLon =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    _mapController.move(LatLng(centerLat, centerLon), 17);
  }

  // ============================================================
  // ✅ SUPPRESSION ZONE - NOUVEAU
  // ============================================================
  Future<void> _deleteZone(
      int idZone, int observations, String zoneType) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Supprimer la zone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voulez-vous vraiment supprimer la zone #$idZone ?',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                'Cette zone contient $observations observations.\n'
                'Cette action est irréversible.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final userId = await AuthService().getUserId() ?? 1;

      await _dio.delete(
        '${AppConfig.baseUrl}/zones/$idZone',
        queryParameters: {'user_id': userId},
      );

      // Recharger les zones
      await _loadZones();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zone supprimée avec succès'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ============================================================
  // AFFICHAGE DES DÉTAILS D'UNE ZONE - AVEC BOUTON SUPPRIMER
  // ============================================================
  void _showZoneDetails(ZoneData zone) {
    String titre = 'Zone #${zone.id}';
    String sousTitre = '';
    Color couleur = _getZoneColor(zone.zoneType, zone.couleur);

    if (zone.zoneType == "DANS_PARCELLE") {
      sousTitre = '📍 ${zone.parcelleNom ?? 'Parcelle inconnue'}';
    } else if (zone.zoneType == "HORS_PARCELLE") {
      sousTitre = '⚠️ Hors parcelle';
    } else {
      sousTitre = '🔗 Multi-parcelles';
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: couleur),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titre,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        if (sousTitre.isNotEmpty)
                          Text(sousTitre,
                              style: TextStyle(fontSize: 12, color: couleur)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow(Icons.people, 'Observations',
                  '${zone.nombreObservations} observations'),
              _buildDetailRow(Icons.circle, 'Rayon',
                  '${zone.rayon.toStringAsFixed(1)} mètres'),
              _buildDetailRow(Icons.info, 'Niveau', _getNiveauAlerte(zone)),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Bouton Centrer
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _mapController.move(
                            LatLng(zone.latitude, zone.longitude), 16);
                      },
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Centrer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ✅ Bouton Supprimer
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteZone(
                            zone.id, zone.nombreObservations, zone.zoneType);
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Supprimer',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _getNiveauAlerte(ZoneData zone) {
    if (zone.zoneType == "HORS_PARCELLE") return "Information";
    if (zone.nombreObservations >= 20) return "Critique ⚠️";
    if (zone.nombreObservations >= 10) return "Actif";
    return "Émergent";
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final allMarkers = <Marker>[
      ..._zoneMarkers,
      if (_userMarker != null) _userMarker!,
      ..._parcelMarkers,
    ];
    if (_highlightMarker != null) allMarkers.add(_highlightMarker!);

    final polygons = <Polygon>[
      ..._parcelPolygons,
      if (_isDrawingParcel && _parcelPoints.isNotEmpty)
        Polygon(
          points: _parcelPoints,
          color: Colors.red.withValues(alpha: 0.2),
          borderColor: Colors.red,
          borderStrokeWidth: 2.5,
          isDotted: true,
        ),
    ];

    final drawingMarkers = _isDrawingParcel
        ? _parcelPoints
            .asMap()
            .entries
            .map((entry) => Marker(
                  point: entry.value,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ))
            .toList()
        : <Marker>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zones infectées',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isDrawingParcel)
            IconButton(
                icon: const Icon(Icons.draw),
                onPressed: _startDrawingParcel,
                color: Colors.red.shade700),
          IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _centerOnUser,
              color: AppTheme.primary),
          IconButton(
            icon: Icon(_isSatellite ? Icons.map : Icons.satellite),
            onPressed: () => setState(() => _isSatellite = !_isSatellite),
            color: AppTheme.primary,
          ),
          IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _showLegendDialog,
              color: AppTheme.primary),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            color: AppTheme.primary,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 8,
              maxZoom: 18,
              onTap: (tapPosition, point) {
                if (_isDrawingParcel) _addPointToParcel(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _isSatellite
                    ? 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tomscan.app',
              ),
              PolygonLayer(polygons: polygons),
              MarkerLayer(markers: [...allMarkers, ...drawingMarkers]),
            ],
          ),
          if (_isLocating)
            Positioned(
              top: 70,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Recherche de votre position...'),
                    ),
                  ],
                ),
              ),
            ),
          if (_errorMessage != null && _userPosition == null && !_isLocating)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      _errorMessage!.contains('dernière localisation')
                          ? Icons.gps_fixed
                          : Icons.gps_off,
                      size: 40,
                      color: _errorMessage!.contains('dernière localisation')
                          ? Colors.orange
                          : Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isLoadingData && !_isLocating)
            Positioned(
              top: 16,
              left: 16,
              child: Material(
                elevation: 4,
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      const Text('Chargement des données...'),
                    ],
                  ),
                ),
              ),
            ),
          if (_isDrawingParcel)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${_parcelPoints.length}',
                            style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Text('points', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _cancelDrawing,
                          style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12)),
                          child: const Text('Annuler'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _saveParcel,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Terminer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_isDrawingParcel)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.red.shade600, Colors.red.shade800]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.draw, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Mode dessin',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Légende',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 10)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('≥20 (parcelle)', style: TextStyle(fontSize: 9))
                  ]),
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Colors.orange, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('10-19 (parcelle)',
                        style: TextStyle(fontSize: 9))
                  ]),
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.amber, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('<10 (parcelle)', style: TextStyle(fontSize: 9))
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.orange, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('Hors parcelle', style: TextStyle(fontSize: 9))
                  ]),
                  if (_userParcels.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(height: 0.5, color: Colors.grey.shade300),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(width: 10, height: 2, color: Colors.red),
                      const SizedBox(width: 4),
                      const Text('Parcelle', style: TextStyle(fontSize: 9))
                    ]),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(_isSatellite ? Icons.satellite : Icons.map,
                      size: 12, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  Text(_isSatellite ? 'Satellite' : 'Plan',
                      style: const TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LÉGENDE
  // ============================================================
  void _showLegendDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Légende'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLegendItem(
                  Colors.red, 'Zone dans parcelle - Critique (≥20 obs)'),
              const SizedBox(height: 8),
              _buildLegendItem(
                  Colors.orange, 'Zone dans parcelle - Active (10-19 obs)'),
              const SizedBox(height: 8),
              _buildLegendItem(
                  Colors.amber, 'Zone dans parcelle - Émergente (<10 obs)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  const Text('Zone hors parcelle (information)'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(width: 16, height: 3, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Point de diagnostic récent'),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const Text(
                'Appuyez sur ✏️ pour dessiner une parcelle',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 12),
          SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Color _getZoneColor(String zoneType, String couleur) {
    if (zoneType == "DANS_PARCELLE") {
      if (couleur == 'red') return Colors.red;
      if (couleur == 'orange') return Colors.orange;
      return Colors.amber;
    } else if (zoneType == "HORS_PARCELLE") {
      return Colors.orange;
    } else {
      return Colors.red.shade900;
    }
  }
}

class ZoneData {
  final int id;
  final double latitude;
  final double longitude;
  final double rayon;
  final int nombreObservations;
  final String couleur;
  final String zoneType;
  final String? parcelleNom;
  final String popupText;

  ZoneData({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.rayon,
    required this.nombreObservations,
    required this.couleur,
    required this.zoneType,
    this.parcelleNom,
    required this.popupText,
  });
}

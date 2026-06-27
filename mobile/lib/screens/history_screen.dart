import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../services/local_database_service.dart';
import 'result_screen.dart';
import 'realtime_result_screen.dart';
import 'map_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Dio _dio = Dio();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _error;

  String _selectedFilterType = 'tous';
  String? _selectedMaladie;
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _maladies = [];

  final LocalDatabaseService _db = LocalDatabaseService();

  @override
  void initState() {
    super.initState();
    _initLocalDb();
    _loadMaladies();
    _loadHistory();
  }

  Future<void> _initLocalDb() async {
    final userId = await AuthService().getUserId();
    if (userId != null) {
      _db.setUserId(userId);
      debugPrint('📱 Base locale initialisée pour l\'utilisateur $userId');
    }
  }

  Future<void> _loadMaladies() async {
    try {
      final response = await _dio.get('${AppConfig.baseUrl}/maladies');
      if (response.statusCode == 200) {
        setState(() {
          _maladies = List<Map<String, dynamic>>.from(response.data);
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement maladies: $e');
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // ============================================================
    // 1. CHARGER LE CACHE LOCAL (INSTANTANÉ)
    // ============================================================
    try {
      final localItems = await _db.getHistoryItems(limit: 50);
      if (localItems.isNotEmpty) {
        debugPrint(
            '📱 Chargé ${localItems.length} éléments depuis le cache local');
        setState(() {
          _items = localItems.map((item) {
            final data = item['data'] as String;
            final parsedData = json.decode(data) as Map<String, dynamic>;
            return {
              ...parsedData,
              '_local_id': item['id'],
              'date': item['date'] ?? parsedData['date'],
              'type': item['type'] ?? parsedData['type'] ?? 'photo',
            };
          }).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement local: $e');
      setState(() {
        _isLoading = false;
      });
    }

    // ============================================================
    // 2. MISE À JOUR EN ARRIÈRE-PLAN (avec déduplication)
    // ============================================================
    _syncWithServer();
  }

  Future<void> _syncWithServer() async {
    try {
      final userId = await AuthService().getUserId() ?? 1;

      // ============================================================
      // RÉCUPÉRER TOUTES LES DONNÉES DU SERVEUR
      // ============================================================
      final allQueryParams = <String, dynamic>{
        'user_id': userId,
        'limit': 100,
      };

      final allResponse = await _dio.get(
        '${AppConfig.baseUrl}/history',
        queryParameters: allQueryParams,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (allResponse.statusCode == 200) {
        final allData = allResponse.data;
        final allItems = List<Map<String, dynamic>>.from(allData['items']);

        debugPrint('📡 Récupéré ${allItems.length} éléments depuis le serveur');

        // ============================================================
        // SAUVEGARDER UNIQUEMENT LES ÉLÉMENTS QUI N'EXISTENT PAS EN LOCAL
        // ============================================================
        final existingServerIds = <int>{};
        final localItems = await _db.getHistoryItems(limit: 200);
        for (var local in localItems) {
          try {
            final localData = json.decode(local['data'] as String);
            if (localData['id'] is int) {
              existingServerIds.add(localData['id'] as int);
            } else if (localData['id'] is String) {
              final parsed = int.tryParse(localData['id']);
              if (parsed != null) existingServerIds.add(parsed);
            }
          } catch (e) {
            debugPrint('Erreur parsing local: $e');
          }
        }

        int newItemsCount = 0;
        for (var item in allItems) {
          final serverId = item['id'];
          if (serverId != null && !existingServerIds.contains(serverId)) {
            try {
              await _db.saveHistoryItem(
                item['type'] ?? 'photo',
                item['date'] ?? DateTime.now().toIso8601String(),
                {...item, '_synced': true},
              );
              newItemsCount++;
            } catch (e) {
              debugPrint('Erreur sauvegarde locale: $e');
            }
          }
        }

        if (newItemsCount > 0) {
          debugPrint(
              '✅ $newItemsCount nouveaux éléments synchronisés en local');
        }
      }

      // ============================================================
      // CHARGER AVEC LES FILTRES POUR L'AFFICHAGE
      // ============================================================
      final queryParams = <String, dynamic>{
        'user_id': userId,
        'limit': 50,
      };

      if (_selectedFilterType != 'tous') {
        queryParams['type'] = _selectedFilterType;
      }
      if (_selectedMaladie != null && _selectedMaladie!.isNotEmpty) {
        queryParams['maladie'] = _selectedMaladie;
      }
      if (_startDate != null) {
        queryParams['date_debut'] = _startDate!.toIso8601String().split('T')[0];
      }
      if (_endDate != null) {
        queryParams['date_fin'] = _endDate!.toIso8601String().split('T')[0];
      }

      final response = await _dio.get(
        '${AppConfig.baseUrl}/history',
        queryParameters: queryParams,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final items = List<Map<String, dynamic>>.from(data['items']);

        if (mounted) {
          setState(() {
            _items = items;
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur synchronisation: $e');
      // Ne pas afficher d'erreur à l'utilisateur car on a déjà les données locales
    }
  }

  // ============================================================
  // SUPPRESSION CORRIGÉE
  // ============================================================
  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
            const SizedBox(width: 10),
            Text(
              'Confirmer la suppression',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        content: Text(
          item['type'] == 'photo'
              ? 'Voulez-vous vraiment supprimer le diagnostic #${item['id']} ? Cette action est irréversible.'
              : 'Voulez-vous vraiment supprimer la session #${item['id']} ? Cette action est irréversible.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textMedium,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textMedium,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Supprimer'),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );

    if (confirm != true) return;

    try {
      // ✅ Récupérer l'ID de l'utilisateur connecté
      final userId = await AuthService().getUserId();
      if (userId == null) {
        throw Exception('Utilisateur non connecté');
      }

      final itemType = item['type'] ?? 'photo';
      final itemId = item['id'];

      // ✅ Construire l'endpoint avec user_id en query param
      String endpoint;
      if (itemType == 'photo') {
        endpoint = '${AppConfig.baseUrl}/diagnostics/$itemId';
      } else {
        endpoint = '${AppConfig.baseUrl}/sessions/$itemId';
      }

      // ✅ Envoyer la requête avec user_id
      await _dio.delete(
        endpoint,
        queryParameters: {'user_id': userId},
      );

      // ✅ Supprimer également de la base locale
      final localId = item['_local_id'];
      if (localId != null) {
        await _db.deleteHistoryItem(localId);
      } else {
        await _db.deleteHistoryItemByServerId(itemId);
      }

      if (mounted) {
        setState(() {
          _items.removeWhere((e) => e['id'] == itemId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              itemType == 'photo'
                  ? 'Diagnostic #$itemId supprimé'
                  : 'Session #$itemId supprimée',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ✅ Meilleur message d'erreur
        String errorMessage = 'Erreur lors de la suppression';
        if (e is DioException) {
          if (e.response?.statusCode == 403) {
            errorMessage =
                'Vous n\'avez pas l\'autorisation de supprimer cet élément';
          } else if (e.response?.statusCode == 404) {
            errorMessage = 'Élément non trouvé';
          } else {
            errorMessage =
                e.response?.data['detail'] ?? e.message ?? 'Erreur inconnue';
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $errorMessage'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Date inconnue';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).round();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatConfiance(double? value) {
    if (value == null) return '0.00';
    return value.toStringAsFixed(2);
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.filter_list, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text('Filtrer'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      value: _selectedFilterType,
                      items: const [
                        DropdownMenuItem(value: 'tous', child: Text('Tous')),
                        DropdownMenuItem(value: 'photo', child: Text('Photos')),
                        DropdownMenuItem(
                          value: 'realtime',
                          child: Text('Temps réel'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => _selectedFilterType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      decoration: InputDecoration(
                        labelText: 'Maladie',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      value: _selectedMaladie,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Toutes'),
                        ),
                        ..._maladies.map((m) => DropdownMenuItem(
                              value: m['nom'],
                              child: Text(
                                m['nom']
                                    .replaceAll('_', ' ')
                                    .replaceAll('Tomato ', ''),
                              ),
                            )),
                      ],
                      onChanged: (value) {
                        setStateDialog(() => _selectedMaladie = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setStateDialog(() => _startDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date début',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textLight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _startDate != null
                                        ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                                        : 'Non définie',
                                    style: TextStyle(
                                      color: _startDate != null
                                          ? AppTheme.textDark
                                          : AppTheme.textLight,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _endDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setStateDialog(() => _endDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date fin',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textLight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _endDate != null
                                        ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                                        : 'Non définie',
                                    style: TextStyle(
                                      color: _endDate != null
                                          ? AppTheme.textDark
                                          : AppTheme.textLight,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setStateDialog(() {
                    _selectedFilterType = 'tous';
                    _selectedMaladie = null;
                    _startDate = null;
                    _endDate = null;
                  });
                },
                child: const Text('Réinitialiser'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadHistory();
                },
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Historique'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            color: AppTheme.primary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            color: AppTheme.primary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: AppTheme.danger),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: TextStyle(color: AppTheme.textMedium)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadHistory,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text('Aucun élément dans l\'historique'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final type = item['type'] ?? 'photo';
                        return type == 'photo'
                            ? _buildPhotoItem(item)
                            : _buildRealtimeItem(item);
                      },
                    ),
    );
  }

  Widget _buildPhotoItem(Map<String, dynamic> item) {
    final maladie = item['maladie_nom']?.replaceAll('_', ' ') ?? 'Inconnue';
    final confiance = (item['confiance'] ?? 0).toDouble();
    final date = _formatDate(item['date']);
    final parcelle = item['parcelle_nom'] ?? 'Hors parcelle';
    final latitude = item['latitude'] ?? 0.0;
    final longitude = item['longitude'] ?? 0.0;
    final description = item['description'] ?? '';
    final symptomes = item['symptomes'] ?? '';
    final recommandation = item['recommandation'] ?? '';
    final niveauGravite = item['niveau_gravite'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResultScreen(
                imagePath: item['image_path'] ?? '',
                maladie: item['maladie_nom'] ?? '',
                confiance: confiance,
                idDiagnostic: item['id'],
                idObservation: item['id_observation'] ?? 0,
                latitude: latitude,
                longitude: longitude,
                description: description,
                symptomes: symptomes,
                recommandation: recommandation,
                niveauGravite: niveauGravite,
              ),
            ),
          );
          if (result != null && result['action'] == 'view_on_map' && mounted) {
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
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.photo_camera,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diagnostic #${item['id']}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_formatConfiance(confiance)}%',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteItem(item),
                    color: AppTheme.danger,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                maladie,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on, size: 12, color: AppTheme.textLight),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      parcelle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRealtimeItem(Map<String, dynamic> item) {
    final date = _formatDate(item['date']);
    final duree = _formatDuration(item['duree_secondes'] ?? 0);
    final zones = item['zones_crees'] ?? 0;
    final frames = item['total_frames'] ?? 0;
    final analysees = item['frames_analysees'] ?? 0;
    final taux =
        frames > 0 ? (analysees / frames * 100).toStringAsFixed(1) : '0.0';

    final resumeData = item['resume'] as Map<String, dynamic>? ?? {};
    final maladies = resumeData['maladies_stats'] as Map<String, dynamic>?;
    final maladieNames = maladies?.keys.join(', ') ?? 'Aucune maladie';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          final fullData = {
            'total_frames': item['total_frames'] ?? 0,
            'frames_analysees': item['frames_analysees'] ?? 0,
            'duree_secondes': item['duree_secondes'] ?? 0,
            'maladies_stats': resumeData['maladies_stats'] ?? {},
            'total_observations': resumeData['total_observations'] ?? 0,
            'zones': resumeData['zones'] ?? [],
          };

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RealtimeResultScreen(
                resume: fullData,
                zones: List<Map<String, dynamic>>.from(
                  fullData['zones'] ?? [],
                ),
                sessionId: item['id'],
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      size: 18,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Session #${item['id']}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Temps réel',
                                style: TextStyle(
                                  color: Colors.purple,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteItem(item),
                    color: AppTheme.danger,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                maladieNames,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildInfoChip(Icons.timer, duree),
                  _buildInfoChip(Icons.camera_alt, '$frames'),
                  _buildInfoChip(Icons.check_circle, '$analysees'),
                  _buildInfoChip(Icons.percent, '$taux%'),
                  _buildInfoChip(Icons.location_on, '$zones'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppTheme.textLight),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }
}

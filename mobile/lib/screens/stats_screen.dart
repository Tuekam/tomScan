import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'map_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final Dio _dio = Dio();

  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;

  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _repartition = [];
  List<Map<String, dynamic>> _topZones = [];
  List<Map<String, dynamic>> _topParcelles = [];

  String _selectedPeriode = '30j';
  int? _selectedParcelleId;
  String? _selectedMaladie;
  List<Map<String, dynamic>> _parcelles = [];
  List<Map<String, dynamic>> _maladies = [];

  final List<String> _periodes = ['7j', '30j', '90j', '365j'];
  final Map<String, String> _periodesLabels = {
    '7j': '7 jours',
    '30j': '30 jours',
    '90j': '3 mois',
    '365j': '1 an',
  };

  static const Map<String, Color> _maladieColors = {
    'Mildiou': Color(0xFFEF4444),
    'Alternariose': Color(0xFFF59E0B),
    'Virus jaune': Color(0xFF8B5CF6),
    'Septoriose': Color(0xFF6366F1),
    'Moisissure': Color(0xFFEC4899),
    'Sain': Color(0xFF22C55E),
  };

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadStats();
  }

  Future<int?> _getUserId() async {
    return await AuthService().getUserId();
  }

  Future<void> _loadFilters() async {
    try {
      final userId = await _getUserId() ?? 1;
      final [parcellesRes, maladiesRes] = await Future.wait([
        _dio.get('${AppConfig.baseUrl}/parcelles?id_utilisateur=$userId'),
        _dio.get('${AppConfig.baseUrl}/maladies'),
      ]);

      setState(() {
        _parcelles = List<Map<String, dynamic>>.from(parcellesRes.data);
        _maladies = List<Map<String, dynamic>>.from(maladiesRes.data);
      });
    } catch (e) {
      debugPrint('Erreur chargement filtres: $e');
    }
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = await _getUserId() ?? 1;
      final queryParams = {
        'periode': _selectedPeriode,
        'user_id': userId,
        if (_selectedParcelleId != null) 'parcelle_id': _selectedParcelleId,
        if (_selectedMaladie != null) 'maladie': _selectedMaladie,
      };

      final response = await _dio.get(
        '${AppConfig.baseUrl}/stats',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        setState(() {
          _stats = response.data;
          _repartition = List<Map<String, dynamic>>.from(
              _stats['repartition_maladies'] ?? []);
          _topZones =
              List<Map<String, dynamic>>.from(_stats['top_zones'] ?? []);
          _topParcelles =
              List<Map<String, dynamic>>.from(_stats['top_parcelles'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedParcelleId = null;
      _selectedMaladie = null;
      _selectedPeriode = '30j';
    });
    _loadStats();
  }

  // ============================================================
  // EXPORT DES ZONES EN CSV
  // ============================================================
  Future<void> _exportZones() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      final userId = await _getUserId() ?? 1;

      final queryParams = {
        'user_id': userId,
        'periode': _selectedPeriode,
        if (_selectedParcelleId != null) 'parcelle_id': _selectedParcelleId,
        if (_selectedMaladie != null) 'maladie': _selectedMaladie,
      };

      final response = await _dio.get(
        '${AppConfig.baseUrl}/export/zones',
        queryParameters: queryParams,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        final bytes = response.data as List<int>;

        final now = DateTime.now();
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        String filename =
            'zones_infectees_${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_${twoDigits(now.hour)}${twoDigits(now.minute)}.csv';
        final disposition = response.headers['content-disposition']?.first;
        if (disposition != null && disposition.contains('filename=')) {
          final match = RegExp(r'filename=([^;]+)').firstMatch(disposition);
          if (match != null) {
            filename = match.group(1)!.replaceAll('"', '');
          }
        }

        await Share.shareXFiles(
          [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: filename,
              mimeType: 'text/csv',
            )
          ],
          text: '📊 Export des zones infectées - TomScan',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Export terminé: $filename'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Erreur lors de l\'export');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur export: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // ============================================================
  // ✅ ZONE DETAIL - CORRIGÉ AVEC user_id
  // ============================================================
  Future<void> _showZoneDetail(Map<String, dynamic> zone) async {
    try {
      // ✅ Récupérer l'ID de l'utilisateur
      final userId = await _getUserId() ?? 1;

      // ✅ Envoyer user_id en query param
      final response = await _dio.get(
        '${AppConfig.baseUrl}/stats/zone/${zone['id_zone']}',
        queryParameters: {'user_id': userId},
      );

      if (response.statusCode == 200 && mounted) {
        final detail = response.data;
        if (detail.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(detail['error']), backgroundColor: Colors.orange),
          );
          return;
        }
        _showDetailBottomSheet(detail);
      }
    } catch (e) {
      debugPrint('Erreur chargement détail zone: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showParcelleDetail(Map<String, dynamic> parcelle) async {
    try {
      final response = await _dio.get(
          '${AppConfig.baseUrl}/parcelles/${parcelle['id_parcelle']}/stats');

      if (response.statusCode == 200 && mounted) {
        final detail = response.data;
        _showParcelleDetailBottomSheet(parcelle, detail);
      }
    } catch (e) {
      debugPrint('Erreur chargement détail parcelle: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showDetailBottomSheet(Map<String, dynamic> detail) {
    final maladies = List<Map<String, dynamic>>.from(detail['maladies'] ?? []);
    final total = detail['total_observations'] ?? 0;

    if (maladies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aucune donnée disponible pour cette zone'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    int totalMalades = 0;
    for (var m in maladies) {
      if (m['nom'] != 'Sain') {
        totalMalades += (m['count'] as int? ?? 0);
      }
    }
    final tauxZone =
        total > 0 ? (totalMalades / total * 100).toStringAsFixed(0) : '0';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Zone ${detail['id_zone']}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: AppTheme.textMedium),
                const SizedBox(width: 4),
                Text(
                  detail['parcelle_nom'] ?? 'Hors parcelle',
                  style: TextStyle(color: AppTheme.textMedium),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Taux: $tauxZone%',
                    style: TextStyle(
                        color: AppTheme.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text('RÉPARTITION PAR MALADIE',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 16),
            ...maladies.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _getMaladieDisplayName(m['nom']),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Text(
                            '${m['count']} observations (${m['pourcentage']}%)',
                            style: TextStyle(
                                color: AppTheme.textMedium, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (m['count'] as int? ?? 0) / total,
                          backgroundColor: Colors.grey.shade200,
                          color: _getMaladieColor(m['nom']),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapScreen(
                        initialLatitude: detail['centre']['lat'],
                        initialLongitude: detail['centre']['lon'],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.map),
                label: const Text('Voir sur la carte'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showParcelleDetailBottomSheet(
      Map<String, dynamic> parcelle, Map<String, dynamic> stats) {
    final total = stats['total_observations'] ?? 0;
    final malades = stats['observations_malades'] ?? 0;
    final taux = stats['taux_infection'] ?? 0;
    final details =
        List<Map<String, dynamic>>.from(stats['details_par_maladie'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.agriculture, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    parcelle['nom'],
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard('Total obs', total.toString()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                      'Observations malades', malades.toString()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                      "Taux d'infection", '${taux.toStringAsFixed(1)}%'),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text('RÉPARTITION PAR MALADIE',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 16),
            if (details.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: Text('Aucune donnée',
                        style: TextStyle(color: Colors.grey))),
              )
            else
              ...details.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _getMaladieDisplayName(
                                  m['maladie_nom'] ?? 'Inconnue'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const Spacer(),
                            Text(
                              '${m['count']} observations',
                              style: TextStyle(
                                  color: AppTheme.textMedium, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (m['count'] as int? ?? 0) / total,
                            backgroundColor: Colors.grey.shade200,
                            color: _getMaladieColor(m['maladie_nom'] ?? ''),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
                label: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getMaladieDisplayName(String nom) {
    String clean = nom.replaceAll('_', ' ').trim();

    if (clean.contains('Early') && clean.contains('Blight'))
      return 'Alternariose';
    if (clean.contains('Healthy')) return 'Sain';
    if (clean.contains('late') && clean.contains('blight')) return 'Mildiou';
    if (clean.contains('yellow') || clean.contains('curl'))
      return 'Virus jaune';
    if (clean.contains('mold')) return 'Moisissure';
    if (clean.contains('septoria') || clean.contains('spot'))
      return 'Septoriose';

    if (_maladieColors.containsKey(clean)) return clean;

    return clean;
  }

  Color _getMaladieColor(String nom) {
    if (_maladieColors.containsKey(nom)) {
      return _maladieColors[nom]!;
    }

    final display = _getMaladieDisplayName(nom);
    return _maladieColors[display] ?? Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          // EXPORT
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            onPressed: _isExporting ? null : _exportZones,
            tooltip: 'Exporter les zones en CSV',
            color: AppTheme.primary,
          ),
          // RAFRAÎCHIR
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
            color: AppTheme.primary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
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
                          onPressed: _loadStats,
                          child: const Text('Réessayer')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildStatCard(Icons.photo_camera, 'Diagnostics',
                              _stats['total_diagnostics'] ?? 0),
                          const SizedBox(width: 12),
                          _buildStatCard(Icons.warning_amber_rounded, 'Zones',
                              _stats['total_zones'] ?? 0),
                          const SizedBox(width: 12),
                          _buildStatCard(Icons.agriculture, 'Parcelles',
                              _stats['total_parcelles'] ?? 0),
                          const SizedBox(width: 12),
                          _buildStatCard(Icons.trending_up, 'Infection',
                              '${_stats['taux_infection_moyen'] ?? 0}%'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text('FILTRES',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                  ),
                                  TextButton(
                                    onPressed: _resetFilters,
                                    child: const Text('Réinitialiser'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildPeriodDropdown()),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildParcelleDropdown()),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildMaladieDropdown(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_repartition.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.pie_chart,
                                        size: 20, color: AppTheme.primary),
                                    const SizedBox(width: 8),
                                    const Text('RÉPARTITION DES MALADIES',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 180,
                                  child: _buildPieChart(),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: _repartition
                                      .map((m) => Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: _getMaladieColor(
                                                      m['nom']),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${_getMaladieDisplayName(m['nom'])}: ${m['count']} (${m['pourcentage']}%)',
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.leaderboard,
                                      size: 20, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  const Text('ZONES LES PLUS INFECTÉES',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (_topZones.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                      child: Text('Aucune zone',
                                          style:
                                              TextStyle(color: Colors.grey))),
                                )
                              else
                                _buildHorizontalBarChartZones(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.agriculture,
                                      size: 20, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  const Text('PARCELLES LES PLUS TOUCHÉES',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (_topParcelles.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                      child: Text('Aucune parcelle',
                                          style:
                                              TextStyle(color: Colors.grey))),
                                )
                              else
                                _buildHorizontalBarChartParcelles(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, dynamic value) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 24, color: AppTheme.primary),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPeriode,
          isExpanded: true,
          items: _periodes
              .map((p) => DropdownMenuItem<String>(
                    value: p,
                    child: Text(_periodesLabels[p]!),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _selectedPeriode = v);
              _loadStats();
            }
          },
        ),
      ),
    );
  }

  Widget _buildParcelleDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _selectedParcelleId,
          isExpanded: true,
          hint: const Text('Toutes parcelles'),
          items: [
            const DropdownMenuItem<int?>(
                value: null, child: Text('Toutes parcelles')),
            ..._parcelles.map((p) => DropdownMenuItem<int?>(
                  value: p['id'],
                  child: Text(p['nom']),
                )),
          ],
          onChanged: (v) {
            setState(() => _selectedParcelleId = v);
            _loadStats();
          },
        ),
      ),
    );
  }

  Widget _buildMaladieDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedMaladie,
          isExpanded: true,
          hint: const Text('Toutes maladies'),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('Toutes maladies')),
            ..._maladies.map((m) => DropdownMenuItem<String?>(
                  value: m['nom'],
                  child: Text(_getMaladieDisplayName(m['nom'])),
                )),
          ],
          onChanged: (v) {
            setState(() => _selectedMaladie = v);
            _loadStats();
          },
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    if (_repartition.isEmpty) return const SizedBox.shrink();

    final sections = <PieChartSectionData>[];
    for (var m in _repartition) {
      sections.add(
        PieChartSectionData(
          value: (m['pourcentage'] ?? 0).toDouble(),
          title: '${m['pourcentage']}%',
          color: _getMaladieColor(m['nom']),
          radius: 70,
          titleStyle: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }
    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 35,
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildHorizontalBarChartZones() {
    final maxObs = _topZones.isNotEmpty
        ? (_topZones.first['nombre_observations'] as num).toDouble()
        : 1;

    return Column(
      children: _topZones.take(5).toList().asMap().entries.map((entry) {
        final index = entry.key + 1;
        final zone = entry.value;
        final obs = (zone['nombre_observations'] as num).toDouble();
        final pourcentage = (obs / maxObs * 100).clamp(0, 100);
        final zoneType = zone['parcelle_nom'] ?? 'Hors parcelle';

        return GestureDetector(
          onTap: () => _showZoneDetail(zone),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        '$index.',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Zone ${zone['id_zone']}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            zoneType,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${obs.toInt()} obs',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 30),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pourcentage / 100,
                          backgroundColor: Colors.grey.shade200,
                          color: AppTheme.primary,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${pourcentage.toStringAsFixed(0)}%',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHorizontalBarChartParcelles() {
    final maxTaux = _topParcelles.isNotEmpty
        ? (_topParcelles.first['taux_infection'] as num).toDouble()
        : 1;

    return Column(
      children: _topParcelles.take(5).toList().asMap().entries.map((entry) {
        final index = entry.key + 1;
        final parcelle = entry.value;
        final taux = (parcelle['taux_infection'] as num).toDouble();
        final pourcentage = (taux / maxTaux * 100).clamp(0, 100);

        return GestureDetector(
          onTap: () => _showParcelleDetail(parcelle),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        '$index.',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        parcelle['nom'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '${taux.toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, color: AppTheme.danger),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 30),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pourcentage / 100,
                          backgroundColor: Colors.grey.shade200,
                          color: taux > 50
                              ? AppTheme.danger
                              : (taux > 20 ? AppTheme.secondary : Colors.green),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${taux.toStringAsFixed(0)}%',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

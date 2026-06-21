// screens/admin/admin_global_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme.dart';
import '../../config.dart';
import '../../services/auth_service.dart';

class AdminGlobalStatsScreen extends StatefulWidget {
  const AdminGlobalStatsScreen({super.key});

  @override
  State<AdminGlobalStatsScreen> createState() => _AdminGlobalStatsScreenState();
}

class _AdminGlobalStatsScreenState extends State<AdminGlobalStatsScreen> {
  final Dio _dio = Dio();
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _error;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    _token = await AuthService().getToken();

    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/admin/global-stats',
        queryParameters: {'token': _token},
      );

      if (response.statusCode == 200) {
        setState(() {
          _stats = response.data;
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

  Color _getMaladieColor(String nom) {
    if (nom.contains('healthy')) return Colors.green;
    if (nom.contains('Late')) return Colors.red;
    if (nom.contains('Early')) return Colors.orange;
    if (nom.contains('yellow')) return Colors.purple;
    if (nom.contains('mold')) return Colors.pink;
    if (nom.contains('Septoria')) return Colors.indigo;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: AppTheme.textMedium)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadStats,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cartes KPI
                    const Text(
                      'Indicateurs clés',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildKpiCard('Utilisateurs',
                            '${_stats['total_users'] ?? 0}', AppTheme.primary),
                        const SizedBox(width: 12),
                        _buildKpiCard(
                            'Diagnostics',
                            '${_stats['total_diagnostics'] ?? 0}',
                            AppTheme.primaryLight),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildKpiCard(
                            'Parcelles',
                            '${_stats['total_parcelles'] ?? 0}',
                            AppTheme.secondary),
                        const SizedBox(width: 12),
                        _buildKpiCard('Zones', '${_stats['total_zones'] ?? 0}',
                            AppTheme.danger),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Top maladies
                    if (_stats['top_maladies'] != null &&
                        (_stats['top_maladies'] as List).isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Top 5 maladies',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...(_stats['top_maladies'] as List).map((m) {
                              final nom = (m['maladie_nom'] ?? 'Inconnue')
                                  .replaceAll('_', ' ')
                                  .replaceAll('Tomato ', '');
                              final count = m['count'] ?? 0;
                              final total =
                                  (_stats['total_observations'] ?? 1) as int;
                              final pourcentage =
                                  total > 0 ? (count / total * 100) : 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: _getMaladieColor(nom),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            nom,
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        Text(
                                          '$count (${pourcentage.toStringAsFixed(0)}%)',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: count / total,
                                        backgroundColor: Colors.grey.shade200,
                                        color: _getMaladieColor(nom),
                                        minHeight: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Top utilisateurs
                    if (_stats['top_users'] != null &&
                        (_stats['top_users'] as List).isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Top 5 utilisateurs',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...(_stats['top_users'] as List)
                                .asMap()
                                .entries
                                .map((entry) {
                              final index = entry.key + 1;
                              final user = entry.value;
                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$index',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user['nom'] ?? 'Inconnu',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                          Text(
                                            'ID: ${user['id_utilisateur']}',
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
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${user['diagnostic_count'] ?? 0}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Évolution
                    if (_stats['evolution'] != null &&
                        (_stats['evolution'] as List).isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Évolution des diagnostics',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 180,
                              child: _buildLineChart(),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    final evolution = _stats['evolution'] as List? ?? [];

    if (evolution.isEmpty) {
      return const Center(child: Text('Aucune donnée'));
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < evolution.length; i++) {
      final item = evolution[i];
      spots.add(FlSpot(i.toDouble(), (item['count'] ?? 0).toDouble()));
    }

    final maxY = evolution
        .map((e) => e['count'] as int)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < evolution.length) {
                  final item = evolution[index];
                  final mois = item['mois'] ?? '';
                  return Text(
                    mois.substring(5, 7),
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primaryLight.withValues(alpha: 0.2),
            ),
          ),
        ],
        minY: 0,
        maxY: maxY + 2,
      ),
    );
  }
}

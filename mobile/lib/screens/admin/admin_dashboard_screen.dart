// screens/admin/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme.dart';
import '../../config.dart';
import '../../services/auth_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

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
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Titre
                    Text(
                      'Tableau de bord',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Statistiques globales de la plateforme',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 14,
                        color: AppTheme.textMedium,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Cartes KPI - Responsive
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth;
                        final crossAxisCount = maxWidth < 400 ? 2 : 4;
                        final spacing = maxWidth < 400 ? 8.0 : 12.0;

                        return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: 1.1,
                          children: [
                            _buildKpiCard(
                              'Utilisateurs',
                              '${_stats['total_users'] ?? 0}',
                              Icons.people,
                              AppTheme.primary,
                            ),
                            _buildKpiCard(
                              'Diagnostics',
                              '${_stats['total_diagnostics'] ?? 0}',
                              Icons.photo_camera,
                              AppTheme.primaryLight,
                            ),
                            _buildKpiCard(
                              'Parcelles',
                              '${_stats['total_parcelles'] ?? 0}',
                              Icons.agriculture,
                              AppTheme.secondary,
                            ),
                            _buildKpiCard(
                              'Zones',
                              '${_stats['total_zones'] ?? 0}',
                              Icons.warning_amber_rounded,
                              AppTheme.danger,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Graphique : Répartition des maladies (Camembert)
                    if (_stats['top_maladies'] != null &&
                        (_stats['top_maladies'] as List).isNotEmpty)
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Répartition des maladies',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: isSmallScreen ? 180 : 220,
                              child: _buildPieChart(),
                            ),
                            const SizedBox(height: 16),
                            // Légende responsive
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children:
                                  (_stats['top_maladies'] as List).map((m) {
                                final nom = (m['maladie_nom'] ?? 'Inconnue')
                                    .replaceAll('_', ' ')
                                    .replaceAll('Tomato ', '');
                                final count = m['count'] ?? 0;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.background,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _getMaladieColor(nom),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$nom ($count)',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 10 : 11,
                                          color: AppTheme.textMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textLight,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart() {
    final maladies = _stats['top_maladies'] as List? ?? [];
    if (maladies.isEmpty) {
      return const Center(
        child: Text(
          'Aucune donnée',
          style: TextStyle(color: AppTheme.textLight),
        ),
      );
    }

    final total = maladies.fold<double>(
        0.0, (sum, m) => sum + ((m['count'] ?? 0).toDouble()));
    if (total == 0) {
      return const Center(
        child: Text(
          'Aucune donnée',
          style: TextStyle(color: AppTheme.textLight),
        ),
      );
    }

    final sections = <PieChartSectionData>[];
    for (var m in maladies) {
      final count = (m['count'] ?? 0).toDouble();
      final pourcentage = count / total * 100;
      final nom = (m['maladie_nom'] ?? 'Inconnue')
          .replaceAll('_', ' ')
          .replaceAll('Tomato ', '');
      sections.add(
        PieChartSectionData(
          value: count,
          title: '${pourcentage.toStringAsFixed(0)}%',
          color: _getMaladieColor(nom),
          radius: 70,
          titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 30,
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

// screens/admin/admin_user_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme.dart';
import '../../config.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final int userId;
  final String token;

  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    required this.token,
  });

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final Dio _dio = Dio();
  Map<String, dynamic> _data = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/admin/users/${widget.userId}/stats',
        queryParameters: {'token': widget.token},
      );

      if (response.statusCode == 200) {
        setState(() {
          _data = response.data;
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Non renseignée';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final user = _data['user'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          user['nom'] ?? 'Détails utilisateur',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textDark,
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
                        onPressed: _loadUserStats,
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
                      // ==========================================
                      // INFORMATIONS PERSONNELLES COMPLÈTES
                      // ==========================================
                      Container(
                        padding: const EdgeInsets.all(16),
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
                            // En-tête avec avatar
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: AppTheme.primaryLight
                                      .withValues(alpha: 0.2),
                                  child: Text(
                                    user['nom']
                                            ?.substring(0, 1)
                                            .toUpperCase() ??
                                        '?',
                                    style: TextStyle(
                                      fontSize: 24,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['nom'] ?? 'Inconnu',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      Text(
                                        user['email'] ?? 'Email non renseigné',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textLight,
                                        ),
                                      ),
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: user['role'] == 'admin'
                                              ? AppTheme.primary
                                                  .withValues(alpha: 0.1)
                                              : AppTheme.textLight
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'ID: ${user['id']} • ${user['role'] ?? 'agriculteur'}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: user['role'] == 'admin'
                                                ? AppTheme.primary
                                                : AppTheme.textLight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            // Détails personnels
                            _buildDetailRow(
                              Icons.phone_outlined,
                              'Téléphone',
                              user['telephone'] ?? 'Non renseigné',
                            ),
                            _buildDetailRow(
                              Icons.location_on_outlined,
                              'Adresse',
                              user['adresse'] ?? 'Non renseignée',
                            ),
                            _buildDetailRow(
                              Icons.calendar_today_outlined,
                              'Date d\'inscription',
                              _formatDate(user['date_inscription']),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ==========================================
                      // STATISTIQUES DE L'UTILISATEUR
                      // ==========================================
                      Container(
                        padding: const EdgeInsets.all(16),
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
                              'Statistiques',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // KPI - Responsive
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
                                  childAspectRatio: 1.0,
                                  children: [
                                    _buildUserKpi(
                                      'Diagnostics',
                                      '${_data['total_diagnostics'] ?? 0}',
                                      Icons.photo_camera,
                                      AppTheme.primary,
                                    ),
                                    _buildUserKpi(
                                      'Parcelles',
                                      '${_data['total_parcelles'] ?? 0}',
                                      Icons.agriculture,
                                      AppTheme.secondary,
                                    ),
                                    _buildUserKpi(
                                      'Zones',
                                      '${_data['total_zones'] ?? 0}',
                                      Icons.warning_amber_rounded,
                                      AppTheme.danger,
                                    ),
                                    _buildUserKpi(
                                      'Observations',
                                      '${_data['total_observations'] ?? 0}',
                                      Icons.visibility,
                                      Colors.purple,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ==========================================
                      // RÉPARTITION DES MALADIES (Camembert + Légende)
                      // ==========================================
                      if (_data['maladies'] != null &&
                          (_data['maladies'] as List).isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                height: isSmallScreen ? 160 : 200,
                                child: _buildUserPieChart(),
                              ),
                              const SizedBox(height: 16),
                              // Légende
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: (_data['maladies'] as List).map((m) {
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
                ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textMedium),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMedium,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textDark,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserKpi(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
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

  Widget _buildUserPieChart() {
    final maladies = _data['maladies'] as List? ?? [];
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
        centerSpaceRadius: 25,
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

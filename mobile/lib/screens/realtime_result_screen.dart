import 'package:flutter/material.dart';
import '../theme.dart';
import 'map_screen.dart';

class RealtimeResultScreen extends StatelessWidget {
  final Map<String, dynamic> resume;
  final List<Map<String, dynamic>> zones;
  final int? sessionId;

  const RealtimeResultScreen({
    super.key,
    required this.resume,
    required this.zones,
    this.sessionId,
  });

  // ✅ Noms affichés pour les maladies
  String _getDisplayName(String nom) {
    final Map<String, String> displayNames = {
      'Tomato_Early_Blight': 'Alternariose',
      'Tomato_healthy': 'Sain',
      'Tomato_Late_blight': 'Mildiou',
      'Tomato_leaf_yellow_curl_virus': 'Virus jaune',
      'Tomato_mold': 'Moisissure',
      'Tomato_powdery_mildew': 'Oïdium', // ← NOUVEAU !
      'Tomato_Septoria_leaf_spot': 'Septoriose',
    };
    return displayNames[nom] ??
        nom.replaceAll('_', ' ').replaceAll('Tomato ', '');
  }

  // ✅ Couleurs pour les 7 classes
  Color _getMaladieColor(String nom) {
    switch (nom) {
      case 'Tomato_Early_Blight':
        return Colors.orange;
      case 'Tomato_healthy':
        return Colors.green;
      case 'Tomato_Late_blight':
        return Colors.red;
      case 'Tomato_leaf_yellow_curl_virus':
        return Colors.purple;
      case 'Tomato_mold':
        return Colors.pink;
      case 'Tomato_powdery_mildew': // ← NOUVEAU !
        return Colors.blue.shade700;
      case 'Tomato_Septoria_leaf_spot':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalFrames = resume['total_frames'] ?? 0;
    final framesAnalysees = resume['frames_analysees'] ?? 0;
    final dureeSecondes = resume['duree_secondes'] ?? 0;
    final taux = totalFrames > 0
        ? (framesAnalysees / totalFrames * 100).toStringAsFixed(1)
        : '0.0';

    final maladiesStats = Map<String, int>.from(resume['maladies_stats'] ?? {});
    final totalObs = resume['total_observations'] ?? 0;
    final sortedMaladies = maladiesStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title:
            Text(sessionId != null ? 'Session #$sessionId' : 'Résumé du scan'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scan terminé avec succès',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Durée: ${dureeSecondes.toStringAsFixed(1)} secondes',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Cartes KPI
            Row(
              children: [
                _buildKpiCard(
                  Icons.camera_alt,
                  'Frames totales',
                  '$totalFrames',
                ),
                const SizedBox(width: 12),
                _buildKpiCard(
                  Icons.check_circle,
                  'Analysées',
                  '$framesAnalysees',
                ),
                const SizedBox(width: 12),
                _buildKpiCard(
                  Icons.percent,
                  'Taux',
                  '$taux%',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Répartition des maladies
            if (sortedMaladies.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.pie_chart,
                            size: 20, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text(
                          'RÉPARTITION PAR MALADIE',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...sortedMaladies.map((entry) {
                      final percentage =
                          totalObs > 0 ? (entry.value / totalObs * 100) : 0;
                      final displayName = _getDisplayName(entry.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '${entry.value} (${percentage.toStringAsFixed(0)}%)',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentage / 100,
                                backgroundColor: Colors.grey.shade200,
                                color: _getMaladieColor(entry.key),
                                minHeight: 6,
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

            // Zones créées
            if (zones.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 20, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text(
                          'ZONES INFECTÉES CRÉÉES',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...zones.asMap().entries.map((entry) {
                      final index = entry.key + 1;
                      final zone = entry.value;
                      final maladies =
                          Map<String, dynamic>.from(zone['maladies'] ?? {});
                      final totalObsZone = zone['observations'] ?? 0;

                      String niveau = '🟡 Émergent';
                      Color couleur = Colors.amber;
                      if (totalObsZone >= 20) {
                        niveau = '🔴 Critique';
                        couleur = Colors.red;
                      } else if (totalObsZone >= 10) {
                        niveau = '🟠 Actif';
                        couleur = Colors.orange;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Zone #${zone['id_zone'] ?? index}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: couleur.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$totalObsZone observations',
                                    style:
                                        TextStyle(fontSize: 12, color: couleur),
                                  ),
                                ),
                                const Spacer(),
                                Text(niveau,
                                    style: TextStyle(
                                        fontSize: 12, color: couleur)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...maladies.entries.map((m) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    '🦠 ${_getDisplayName(m.key)}: ${m.value}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                )),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Boutons d'action
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapScreen(
                            highlightZoneId: zones.isNotEmpty
                                ? zones.first['id_zone']
                                : null,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('Voir sur la carte'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
                label: const Text('Retour à l\'accueil'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

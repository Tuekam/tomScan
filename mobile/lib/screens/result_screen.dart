import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'map_screen.dart';
import 'chatbot_screen.dart';

class ResultScreen extends StatelessWidget {
  final String imagePath;
  final String maladie;
  final double confiance;
  final int idDiagnostic;
  final int idObservation;
  final double latitude;
  final double longitude;
  final String description;
  final String symptomes;
  final String recommandation;
  final String niveauGravite;

  const ResultScreen({
    super.key,
    required this.imagePath,
    required this.maladie,
    required this.confiance,
    required this.idDiagnostic,
    required this.idObservation,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.symptomes,
    required this.recommandation,
    required this.niveauGravite,
  });

  Color _getGraviteColor(String niveau) {
    switch (niveau) {
      case 'ELEVE':
        return Colors.red;
      case 'MOYEN':
        return Colors.orange;
      case 'FAIBLE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getFormattedMaladieName(String name) {
    String clean = name.replaceAll('_', ' ').trim();
    if (clean.toLowerCase().startsWith('tomato ')) {
      clean = clean.substring(7);
    }

    final Map<String, String> frenchNames = {
      'Early Blight': 'Alternariose',
      'Healthy': 'Sain',
      'leaf late blight': 'Mildiou',
      'leaf yellow curl virus': 'Virus jaune',
      'mold leaf': 'Moisissure',
      'powdery mildew': 'Oïdium',
      'septoria leaf spot': 'Septoriose',
    };

    for (var entry in frenchNames.entries) {
      if (clean.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return clean;
  }

  String _getReferenceFolder() {
    final lower = maladie.toLowerCase();
    if (lower.contains('early')) return 'early_blight';
    if (lower.contains('healthy')) return 'healthy';
    if (lower.contains('late')) return 'late_blight';
    if (lower.contains('yellow')) return 'yellow_curl';
    if (lower.contains('mold')) return 'mold';
    if (lower.contains('septoria')) return 'septoria_spot';
    if (lower.contains('powdery') || lower.contains('mildew'))
      return 'powdery_mildew';
    return '';
  }

  List<String> _getReferenceImages() {
    final folder = _getReferenceFolder();
    if (folder.isEmpty) return [];
    return List.generate(
        10, (i) => 'assets/images/references/$folder/img${i + 1}.jpg');
  }

  bool _hasLocalImage() {
    if (imagePath.isEmpty) return false;
    try {
      return File(imagePath).existsSync();
    } catch (e) {
      return false;
    }
  }

  String _getRemoteImageUrl() {
    if (imagePath.isEmpty) return '';
    final fileName = imagePath.split('/').last;
    return '${AppConfig.baseUrlImages}/$fileName';
  }

  @override
  Widget build(BuildContext context) {
    final maladieName = _getFormattedMaladieName(maladie);
    final isHealthy =
        maladie.contains('healthy') || maladie == 'Tomato_healthy';
    final hasLocalImage = _hasLocalImage();
    final remoteUrl = _getRemoteImageUrl();
    final hasRemoteImage = !hasLocalImage && remoteUrl.isNotEmpty;
    final referenceImages = _getReferenceImages();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Résultat du diagnostic',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- Zone image ----------
            if (hasLocalImage)
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(File(imagePath), fit: BoxFit.cover),
                ),
              )
            else if (hasRemoteImage)
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(
                    remoteUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              size: 50, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('Image non disponible',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported,
                          size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Aucune image associée',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // ---------- Badge résultat ----------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isHealthy
                            ? Icons.health_and_safety
                            : Icons.warning_amber_rounded,
                        color: isHealthy ? Colors.green : AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        maladieName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isHealthy ? Colors.green : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Confiance : ${confiance.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  if (niveauGravite.isNotEmpty && !isHealthy)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getGraviteColor(niveauGravite).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Gravité : $niveauGravite',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getGraviteColor(niveauGravite),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ---------- Images de référence ----------
            if (!isHealthy &&
                !maladie.contains('Non identifiable') &&
                referenceImages.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.image, size: 20, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Text('Images de référence',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: referenceImages.length,
                        itemBuilder: (context, index) {
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                referenceImages[index],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image,
                                        color: Colors.grey),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // ---------- Description ----------
            if (description.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 20, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Text('Description',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(description,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // ---------- Symptômes ----------
            if (symptomes.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text('Symptômes',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(symptomes,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // ---------- Recommandation ----------
            if (recommandation.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.agriculture,
                            size: 20, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Recommandation',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(recommandation,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade800)),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // ---------- Boutons ----------
            // ✅ SUPPRIMER LE BOUTON "Voir sur la carte"
            // Les observations ne sont pas affichées sur la carte

            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context, {
                  'action': 'ask_chatbot',
                  'maladie': maladie,
                  'question':
                      'Je viens de diagnostiquer $maladieName sur mes tomates. Que dois-je faire ?',
                });
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Poser une question à TomScan AI'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primaryLight),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Fermer'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

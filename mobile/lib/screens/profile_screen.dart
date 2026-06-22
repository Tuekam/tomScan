// screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Dio _dio = Dio();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isSaving = false;

  Map<String, dynamic> _userData = {};
  List<Map<String, dynamic>> _parcelles = [];
  List<Map<String, dynamic>> _recentActivities = [];

  File? _profileImage;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = await AuthService().getUserId() ?? 1;

      final userRes =
          await _dio.get('${AppConfig.baseUrl}/utilisateur/$userId');
      if (userRes.statusCode == 200) {
        _userData = userRes.data;
        _profileImageUrl = _userData['photo_profil'];
      }

      final parcelleRes = await _dio
          .get('${AppConfig.baseUrl}/parcelles?id_utilisateur=$userId');
      if (parcelleRes.statusCode == 200) {
        _parcelles = List<Map<String, dynamic>>.from(parcelleRes.data);
      }

      await _loadRecentActivities(userId);

      setState(() => _isLoading = false);
    } catch (e) {
      print('Erreur chargement profil: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecentActivities(int userId) async {
    try {
      final historyRes = await _dio.get(
        '${AppConfig.baseUrl}/history',
        queryParameters: {'user_id': userId, 'limit': 5},
      );

      if (historyRes.statusCode == 200) {
        final items = historyRes.data['items'] as List? ?? [];
        _recentActivities = List<Map<String, dynamic>>.from(items);
      }
    } catch (e) {
      print('Erreur chargement activités récentes: $e');
      _recentActivities = [];
    }
  }

  Future<void> _pickProfileImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
      await _uploadProfileImage();
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_profileImage == null) return;

    setState(() => _isSaving = true);

    try {
      final userId = await AuthService().getUserId() ?? 1;
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(_profileImage!.path),
      });

      final response = await _dio.post(
        '${AppConfig.baseUrl}/utilisateur/$userId/photo',
        data: formData,
      );

      if (response.statusCode == 200) {
        _profileImageUrl = response.data['photo_url'];
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo de profil mise à jour'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Erreur upload photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String _getInitiales(String nom) {
    if (nom.isEmpty) return '?';
    final parts = nom.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return nom.substring(0, 1).toUpperCase();
  }

  String _getImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '${AppConfig.baseUrlImages}${path.replaceFirst('/api/images', '')}';
  }

  // ✅ FORMAT DATE CORRIGÉ
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Date inconnue';

    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.isNegative) {
        return '${date.day}/${date.month}/${date.year}';
      }

      if (difference.inSeconds < 60) {
        return 'À l\'instant';
      }
      if (difference.inMinutes < 60) {
        return 'Il y a ${difference.inMinutes} min';
      }
      if (difference.inHours < 24) {
        return 'Il y a ${difference.inHours} h';
      }
      if (difference.inDays < 7) {
        return 'Il y a ${difference.inDays} j';
      }
      if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return 'Il y a $weeks sem';
      }
      if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return 'Il y a $months mois';
      }
      final years = (difference.inDays / 365).floor();
      return 'Il y a $years an${years > 1 ? 's' : ''}';
    } catch (_) {
      return dateStr;
    }
  }

  String _getActivityTitle(Map<String, dynamic> item) {
    final type = item['type'] ?? 'photo';
    if (type == 'photo') {
      return 'Diagnostic photo';
    } else {
      return 'Session temps réel';
    }
  }

  String _getActivitySubtitle(Map<String, dynamic> item) {
    final type = item['type'] ?? 'photo';
    if (type == 'photo') {
      final maladie = item['maladie_nom']?.replaceAll('_', ' ') ?? 'Inconnue';
      return '🦠 $maladie (${item['confiance']?.toStringAsFixed(0) ?? 0}%)';
    } else {
      final zones = item['zones_crees'] ?? 0;
      final frames = item['total_frames'] ?? 0;
      return '📸 $frames frames • 🗺️ $zones zone(s)';
    }
  }

  IconData _getActivityIcon(Map<String, dynamic> item) {
    final type = item['type'] ?? 'photo';
    return type == 'photo' ? Icons.photo_camera : Icons.videocam;
  }

  Color _getActivityColor(Map<String, dynamic> item) {
    final type = item['type'] ?? 'photo';
    return type == 'photo' ? AppTheme.primary : Colors.purple;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textDark,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Carte profil
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _isSaving ? null : _pickProfileImage,
                          child: Stack(
                            children: [
                              Container(
                                width: isSmallScreen ? 64 : 72,
                                height: isSmallScreen ? 64 : 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: _profileImageUrl == null &&
                                          _profileImage == null
                                      ? LinearGradient(
                                          colors: [
                                            AppTheme.primary,
                                            AppTheme.primaryLight
                                          ],
                                        )
                                      : null,
                                  image: _profileImage != null
                                      ? DecorationImage(
                                          image: FileImage(_profileImage!),
                                          fit: BoxFit.cover,
                                        )
                                      : _profileImageUrl != null &&
                                              _profileImageUrl!.isNotEmpty
                                          ? DecorationImage(
                                              image: NetworkImage(_getImageUrl(
                                                  _profileImageUrl!)),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                ),
                                child: _profileImageUrl == null &&
                                        _profileImage == null
                                    ? Center(
                                        child: Text(
                                          _getInitiales(_userData['nom'] ?? ''),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: isSmallScreen ? 22 : 26,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              if (!_isSaving)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              if (_isSaving)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userData['nom'] ?? 'Utilisateur',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 18 : 20,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.work_outline,
                                    size: 14,
                                    color: AppTheme.textMedium,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _userData['role'] ?? 'Agriculteur',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                    color: AppTheme.textLight,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _userData['adresse'] ??
                                          'Adresse non renseignée',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textLight,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Informations personnelles
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Informations personnelles',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          Icons.email_outlined,
                          'Email',
                          _userData['email'] ?? 'Non renseigné',
                        ),
                        _buildInfoRow(
                          Icons.phone_outlined,
                          'Téléphone',
                          _userData['telephone'] ?? 'Non renseigné',
                        ),
                        _buildInfoRow(
                          Icons.location_on_outlined,
                          'Adresse',
                          _userData['adresse'] ?? 'Non renseignée',
                        ),
                        _buildInfoRow(
                          Icons.calendar_today_outlined,
                          'Membre depuis',
                          _userData['date_inscription'] != null
                              ? _formatDate(_userData['date_inscription'])
                              : 'Non renseignée',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Mes parcelles
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.agriculture,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Mes parcelles',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/map');
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Voir tout',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_parcelles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'Aucune parcelle créée',
                                style: TextStyle(color: AppTheme.textLight),
                              ),
                            ),
                          )
                        else
                          ..._parcelles.take(3).map((parcelle) {
                            final surface =
                                (parcelle['surface_ha'] ?? 0.0).toDouble();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                padding:
                                    EdgeInsets.all(isSmallScreen ? 10 : 12),
                                decoration: BoxDecoration(
                                  color: AppTheme.background,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.agriculture,
                                        color: AppTheme.primary,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            parcelle['nom'] ?? 'Parcelle',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textDark,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${surface.toStringAsFixed(2)} ha',
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
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${(parcelle['taux_infection'] ?? 0).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Activité récente
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Activité récente',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/history');
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Voir tout',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_recentActivities.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'Aucune activité récente',
                                style: TextStyle(color: AppTheme.textLight),
                              ),
                            ),
                          )
                        else
                          ..._recentActivities.take(3).map((item) {
                            final date = _formatDate(item['date']);
                            return _buildActivityItem(
                              icon: _getActivityIcon(item),
                              title: _getActivityTitle(item),
                              subtitle: _getActivitySubtitle(item),
                              date: date,
                              color: _getActivityColor(item),
                              isLast: item == _recentActivities.last,
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bouton déconnexion
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _showLogoutDialog(context);
                      },
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Se déconnecter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: BorderSide(
                            color: AppTheme.danger.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textMedium),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
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

  Widget _buildActivityItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required String date,
    required Color color,
    required bool isLast,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMedium,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                date,
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textLight,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
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
            const Text(
              'Déconnexion',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: const Text(
          'Voulez-vous vraiment vous déconnecter ?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textMedium,
            ),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService().logout();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}

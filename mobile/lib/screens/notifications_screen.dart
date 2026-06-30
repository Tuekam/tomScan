// screens/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'map_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Dio _dio = Dio();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _error;

  // ✅ Callback pour mettre à jour le badge
  VoidCallback? _onNotificationsUpdated;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = await AuthService().getUserId();

      final response = await _dio.get(
        '${AppConfig.baseUrl}/notifications',
        queryParameters: {'user_id': userId ?? 1},
      );
      if (response.statusCode == 200) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response.data);
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

  Future<void> _markAsRead(int id) async {
    try {
      await _dio.post('${AppConfig.baseUrl}/notifications/$id/read');
      setState(() {
        final index =
            _notifications.indexWhere((n) => n['id_notification'] == id);
        if (index != -1) {
          _notifications[index]['lu'] = true;
        }
      });
    } catch (e) {
      print('Erreur marquer comme lue: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final userId = await AuthService().getUserId();

      await _dio.post(
        '${AppConfig.baseUrl}/notifications/read-all',
        queryParameters: {'user_id': userId ?? 1},
      );
      setState(() {
        for (var notification in _notifications) {
          notification['lu'] = true;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toutes les notifications marquées comme lues'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Erreur: $e');
    }
  }

  void _openNotification(Map<String, dynamic> notification) {
    // Marquer comme lue
    if (notification['lu'] == false) {
      _markAsRead(notification['id_notification']);
    }

    // Récupérer les coordonnées depuis la notification
    final lat = notification['latitude'] as double?;
    final lon = notification['longitude'] as double?;
    final idZone = notification['id_zone'] as int?;

    if (lat != null && lon != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(
            initialLatitude: lat,
            initialLongitude: lon,
            highlightZoneId: idZone,
            highlightMaladie: notification['titre'],
            highlightConfiance: 100.0,
          ),
        ),
      );
    } else {
      // Si pas de coordonnées, juste ouvrir la carte
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MapScreen(),
        ),
      );
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Date inconnue';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays < 1) {
        if (difference.inHours < 1) {
          return 'Il y a ${difference.inMinutes} min';
        }
        return 'Il y a ${difference.inHours} h';
      } else if (difference.inDays < 7) {
        return 'Il y a ${difference.inDays} j';
      } else {
        return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      return dateStr;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'zone_critique':
        return Icons.warning_amber_rounded;
      case 'zone_creee':
        return Icons.location_on;
      case 'diagnostic':
        return Icons.photo_camera;
      case 'parcelle':
        return Icons.agriculture;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'zone_critique':
        return AppTheme.danger;
      case 'zone_creee':
        return AppTheme.primary;
      case 'diagnostic':
        return Colors.blue;
      case 'parcelle':
        return AppTheme.secondary;
      default:
        return AppTheme.textMedium;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => n['lu'] == false).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textDark,
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              color: AppTheme.primary,
              tooltip: 'Tout marquer comme lu',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
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
                        onPressed: _loadNotifications,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Aucune notification',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Les notifications apparaîtront ici',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
                        final isRead = notification['lu'] == true;
                        final type = notification['type'] ?? 'info';
                        final icon = _getNotificationIcon(type);
                        final color = _getNotificationColor(type);
                        final titre = notification['titre'] ?? 'Notification';
                        final message = notification['message'] ?? '';
                        final date = _formatDate(notification['date_creation']);
                        final hasLocation = notification['latitude'] != null &&
                            notification['longitude'] != null;

                        return GestureDetector(
                          onTap: () => _openNotification(notification),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? Colors.white
                                  : AppTheme.primaryLight.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isRead
                                    ? Colors.grey.shade200
                                    : AppTheme.primary.withOpacity(0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: color,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              titre,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: isRead
                                                    ? FontWeight.w500
                                                    : FontWeight.w600,
                                                color: isRead
                                                    ? AppTheme.textMedium
                                                    : AppTheme.textDark,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isRead)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        message,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isRead
                                              ? AppTheme.textLight
                                              : AppTheme.textMedium,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(
                                            date,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textLight,
                                            ),
                                          ),
                                          if (hasLocation) ...[
                                            const SizedBox(width: 12),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryLight
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.map,
                                                      size: 10,
                                                      color: AppTheme.primary),
                                                  SizedBox(width: 2),
                                                  Text(
                                                    'Voir sur la carte',
                                                    style: TextStyle(
                                                        fontSize: 9,
                                                        color:
                                                            AppTheme.primary),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

// screens/admin/admin_users_list_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../theme.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import 'admin_user_detail_screen.dart';

class AdminUsersListScreen extends StatefulWidget {
  const AdminUsersListScreen({super.key});

  @override
  State<AdminUsersListScreen> createState() => _AdminUsersListScreenState();
}

class _AdminUsersListScreenState extends State<AdminUsersListScreen> {
  final Dio _dio = Dio();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;
  String? _token;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    _token = await AuthService().getToken();

    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/admin/users',
        queryParameters: {'token': _token},
      );

      if (response.statusCode == 200) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(response.data);
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

  Future<void> _deleteUser(int userId, String nom) async {
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
              'Supprimer $nom',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        content: Text(
          'Voulez-vous vraiment supprimer l\'utilisateur "$nom" ?\nToutes ses données seront supprimées définitivement.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textMedium,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _dio.delete(
        '${AppConfig.baseUrl}/admin/users/$userId',
        queryParameters: {'token': _token},
      );

      setState(() {
        _users.removeWhere((u) => u['id'] == userId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Utilisateur supprimé'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    return _users.where((user) {
      final nom = user['nom']?.toLowerCase() ?? '';
      final email = user['email']?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return nom.contains(query) || email.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                        onPressed: _loadUsers,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Barre de recherche
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Rechercher un utilisateur...',
                          hintStyle: TextStyle(color: AppTheme.textLight),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppTheme.textLight,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppTheme.background,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    // Liste
                    Expanded(
                      child: _filteredUsers.isEmpty
                          ? const Center(
                              child: Text(
                                'Aucun utilisateur trouvé',
                                style: TextStyle(color: AppTheme.textLight),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                return _buildUserCard(user);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryLight.withOpacity(0.2),
          child: Text(
            user['nom']?.substring(0, 1).toUpperCase() ?? '?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
        ),
        title: Text(
          user['nom'] ?? 'Inconnu',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user['email'] ?? 'Email non renseigné',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: user['role'] == 'admin'
                    ? AppTheme.primary.withOpacity(0.1)
                    : AppTheme.textLight.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                user['role'] ?? 'agriculteur',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: user['role'] == 'admin'
                      ? AppTheme.primary
                      : AppTheme.textLight,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 20),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminUserDetailScreen(
                      userId: user['id'],
                      token: _token!,
                    ),
                  ),
                );
              },
              color: AppTheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteUser(user['id'], user['nom']),
              color: AppTheme.danger,
            ),
          ],
        ),
      ),
    );
  }
}

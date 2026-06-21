// screens/admin/admin_home_screen.dart
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../services/auth_service.dart';
import 'admin_dashboard_screen.dart';
import 'admin_users_list_screen.dart';
import '../login_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;
  String? _adminName;

  final List<Widget> _screens = [
    const AdminDashboardScreen(),
    const AdminUsersListScreen(),
  ];

  final List<String> _titles = [
    'Dashbord',
    'Utilisateurs',
  ];

  final List<IconData> _icons = [
    Icons.dashboard,
    Icons.people,
  ];

  @override
  void initState() {
    super.initState();
    _loadAdminInfo();
  }

  Future<void> _loadAdminInfo() async {
    final nom = await AuthService().getNom();
    setState(() {
      _adminName = nom;
    });
  }

  Future<void> _logout() async {
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Effacer les données utilisateur
    await AuthService().logout();

    // 2. Naviguer vers la page de connexion et supprimer toutes les routes
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
        (route) => false, // Supprime toutes les routes précédentes
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                size: 20,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _titles[_selectedIndex],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textDark,
        actions: [
          if (_adminName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _adminName!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout_outlined, size: 22),
            onPressed: _logout,
            color: AppTheme.textLight,
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textLight,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: [
            BottomNavigationBarItem(
              icon: Icon(_icons[0]),
              activeIcon: Icon(_icons[0]),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(_icons[1]),
              activeIcon: Icon(_icons[1]),
              label: 'Utilisateurs',
            ),
          ],
        ),
      ),
    );
  }
}

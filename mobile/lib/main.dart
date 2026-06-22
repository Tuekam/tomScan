// main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'services/gps_service.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const TomScanApp());
}

class TomScanApp extends StatefulWidget {
  const TomScanApp({super.key});

  @override
  State<TomScanApp> createState() => _TomScanAppState();
}

class _TomScanAppState extends State<TomScanApp> {
  bool _hasSeenOnboarding = false;
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initGps();
    _checkAppState();
  }

  Future<void> _initGps() async {
    await GpsService().startGpsService();
  }

  Future<void> _checkAppState() async {
    try {
      // 1. Vérifier si l'onboarding a été vu
      final prefs = await SharedPreferences.getInstance();
      final hasSeen = prefs.getBool('has_seen_onboarding') ?? false;

      // 2. Vérifier si l'utilisateur est connecté
      final isLoggedIn = await AuthService().isLoggedIn();

      if (mounted) {
        setState(() {
          _hasSeenOnboarding = hasSeen;
          _isLoggedIn = isLoggedIn;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasSeenOnboarding = false;
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    }
  }

  void _setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TomScan',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _buildHome(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/admin': (context) => const AdminHomeScreen(),
      },
    );
  }

  Widget _buildHome() {
    // Si l'utilisateur n'a pas vu l'onboarding
    if (!_hasSeenOnboarding) {
      return OnboardingScreen(
        onComplete: _setOnboardingSeen,
      );
    }

    // Si l'utilisateur n'est pas connecté
    if (!_isLoggedIn) {
      // Forcer un remplacement de la pile de navigation
      return WillPopScope(
        onWillPop: () async {
          // Empêcher le retour en arrière sur LoginScreen
          return false;
        },
        child: const LoginScreen(),
      );
    }

    // Vérifier le rôle de l'utilisateur
    return FutureBuilder<String?>(
      future: AuthService().getRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final role = snapshot.data ?? 'agriculteur';

        // Si l'utilisateur est admin → AdminHomeScreen
        if (role == 'admin') {
          return const AdminHomeScreen();
        }

        // Sinon → HomeScreen (agriculteur)
        return const HomeScreen();
      },
    );
  }
}

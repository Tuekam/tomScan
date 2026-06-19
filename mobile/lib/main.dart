// main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/gps_service.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initGps();
    _checkOnboardingStatus();
  }

  Future<void> _initGps() async {
    await GpsService().startGpsService();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
        _isLoading = false;
      });
    } catch (e) {
      // En cas d'erreur, on suppose que l'utilisateur n'a pas vu l'onboarding
      setState(() {
        _hasSeenOnboarding = false;
        _isLoading = false;
      });
    }
  }

  void _setOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      setState(() {
        _hasSeenOnboarding = true;
      });
    } catch (e) {
      // Ignorer l'erreur
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
          : _hasSeenOnboarding
              ? const HomeScreen()
              : OnboardingScreen(
                  onComplete: _setOnboardingSeen,
                ),
    );
  }
}

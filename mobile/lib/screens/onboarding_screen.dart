// screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      image: 'assets/images/onboarding/img1.png',
      title: 'Diagnostiquez vos plants',
      subtitle:
          'Prenez une photo de vos feuilles de tomate et obtenez un diagnostic instantané en quelques secondes.',
    ),
    OnboardingPage(
      image: 'assets/images/onboarding/img2.png',
      title: 'Visualisez les zones infectées',
      subtitle:
          'Localisez les foyers de maladie sur la carte et agissez rapidement pour protéger vos cultures.',
    ),
    OnboardingPage(
      image: 'assets/images/onboarding/img3.png',
      title: 'Conseils personnalisés',
      subtitle:
          'Discutez avec notre assistant IA et recevez des recommandations adaptées à votre situation.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Indicateurs de pages
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: screenHeight * 0.02,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppTheme.primary
                          : AppTheme.textLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index], screenHeight, screenWidth);
                },
              ),
            ),
            // Bouton Suivant / Commencer
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: screenHeight * 0.03,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage == _pages.length - 1) {
                      widget.onComplete();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1 ? 'Commencer' : 'Suivant',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(
      OnboardingPage page, double screenHeight, double screenWidth) {
    final isSmallScreen = screenWidth < 380;
    final isLargeScreen = screenWidth > 600;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 60 : 24,
        vertical: 8,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Image responsive
          Container(
            width: double.infinity,
            height: isSmallScreen
                ? screenHeight * 0.30
                : isLargeScreen
                    ? screenHeight * 0.45
                    : screenHeight * 0.38,
            constraints: BoxConstraints(
              minHeight: 180,
              maxHeight: 380,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: DecorationImage(
                image: AssetImage(page.image),
                fit: BoxFit.contain,
              ),
            ),
          ),
          SizedBox(height: screenHeight * 0.04),
          // Titre
          Text(
            page.title,
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: screenHeight * 0.015),
          // Sous-titre
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 8 : 0,
            ),
            child: Text(
              page.subtitle,
              style: TextStyle(
                fontSize: isSmallScreen ? 13 : 15,
                color: AppTheme.textMedium,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final String image;
  final String title;
  final String subtitle;

  OnboardingPage({
    required this.image,
    required this.title,
    required this.subtitle,
  });
}

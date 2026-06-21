// screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import 'admin/admin_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final Dio _dio = Dio();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 380;
    final isLargeScreen = screenWidth > 600;
    final paddingHorizontal =
        isLargeScreen ? 48.0 : (isSmallScreen ? 20.0 : 32.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: paddingHorizontal,
            vertical: 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - MediaQuery.of(context).padding.top - 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isSmallScreen),
                const SizedBox(height: 24),
                if (_errorMessage != null) _buildErrorMessage(),
                _buildEmailField(),
                const SizedBox(height: 16),
                _buildPasswordField(),
                const SizedBox(height: 8),
                _buildForgotPasswordLink(),
                const SizedBox(height: 24),
                _buildLoginButton(isSmallScreen),
                const SizedBox(height: 16),
                _buildRegisterLink(isSmallScreen),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSmall) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary,
                AppTheme.primary.withValues(alpha: 0.7)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.eco,
            size: isSmall ? 26 : 30,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TomScan',
              style: TextStyle(
                fontSize: isSmall ? 22 : 26,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Connectez-vous à votre espace agricole',
              style: TextStyle(
                fontSize: isSmall ? 11 : 13,
                color: AppTheme.textMedium,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.danger.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: AppTheme.danger,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: AppTheme.danger,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    required FocusNode focusNode,
    void Function(String)? onSubmitted,
    bool isDense = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          focusNode: focusNode,
          onSubmitted: onSubmitted,
          textInputAction:
              onSubmitted != null ? TextInputAction.next : TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppTheme.textLight.withValues(alpha: 0.7),
              fontSize: 13,
            ),
            prefixIcon: Icon(
              icon,
              color: focusNode.hasFocus ? AppTheme.primary : AppTheme.textLight,
              size: 20,
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppTheme.primary,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: AppTheme.background,
            contentPadding: EdgeInsets.symmetric(
              vertical: isDense ? 12 : 14,
              horizontal: 16,
            ),
            isDense: isDense,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return _buildTextField(
      controller: _emailController,
      label: 'Adresse email',
      hint: 'jules@tomscan.com',
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      focusNode: _emailFocus,
      onSubmitted: (_) => _passwordFocus.requestFocus(),
    );
  }

  Widget _buildPasswordField() {
    return _buildTextField(
      controller: _passwordController,
      label: 'Mot de passe',
      hint: '••••••••',
      icon: Icons.lock_outline,
      obscureText: _obscurePassword,
      focusNode: _passwordFocus,
      onSubmitted: (_) => _login(),
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: AppTheme.textLight,
          size: 20,
        ),
        onPressed: () {
          setState(() {
            _obscurePassword = !_obscurePassword;
          });
        },
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildForgotPasswordLink() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {
          // TODO: Mot de passe oublié
        },
        child: Text(
          'Mot de passe oublié ?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.primary.withValues(alpha: 0.3),
            decorationThickness: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton(bool isSmall) {
    return SizedBox(
      width: double.infinity,
      height: isSmall ? 48 : 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.5),
        ),
        child: _isLoading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Se connecter',
                    style: TextStyle(
                      fontSize: isSmall ? 14 : 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: isSmall ? 18 : 20,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRegisterLink(bool isSmall) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Pas encore de compte ?',
          style: TextStyle(
            fontSize: isSmall ? 12 : 13,
            color: AppTheme.textMedium,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const RegisterScreen(),
              ),
            );
          },
          child: Text(
            'S\'inscrire',
            style: TextStyle(
              fontSize: isSmall ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primary.withValues(alpha: 0.3),
              decorationThickness: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 📌 CONNEXION AVEC REDIRECTION VERS LE BON ÉCRAN
  // ============================================================
  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Veuillez entrer votre email');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Veuillez entrer votre mot de passe');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/auth/login',
        data: {
          'email': _emailController.text.trim(),
          'mot_de_passe': _passwordController.text,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        await AuthService().saveUserData(
          token: data['token'],
          userId: data['id_utilisateur'],
          nom: data['nom'],
          email: data['email'],
          role: data['role'] ?? 'agriculteur',
        );

        if (!mounted) return;

        // ✅ Rediriger en fonction du rôle
        final role = data['role'] ?? 'agriculteur';
        if (role == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminHomeScreen(),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const HomeScreen(),
            ),
          );
        }
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.response?.data['detail'] ?? 'Erreur de connexion';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Une erreur est survenue';
        _isLoading = false;
      });
    }
  }
}

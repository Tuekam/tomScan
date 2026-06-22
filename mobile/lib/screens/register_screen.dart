// screens/register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../services/local_database_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final Dio _dio = Dio();
  final _nomController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _adresseController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  final LocalDatabaseService _db = LocalDatabaseService();

  // Focus nodes
  final FocusNode _nomFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _telephoneFocus = FocusNode();
  final FocusNode _adresseFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  @override
  void dispose() {
    _nomController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _telephoneController.dispose();
    _adresseController.dispose();
    _nomFocus.dispose();
    _emailFocus.dispose();
    _telephoneFocus.dispose();
    _adresseFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
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

    return WillPopScope(
      onWillPop: () async {
        // ✅ Empêcher le retour en arrière depuis la page d'inscription
        return false;
      },
      child: Scaffold(
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
                minHeight:
                    screenHeight - MediaQuery.of(context).padding.top - 32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Header
                  _buildHeader(isSmallScreen),
                  const SizedBox(height: 20),

                  // ✅ Message d'erreur
                  if (_errorMessage != null) _buildErrorMessage(),

                  // ✅ Formulaire
                  _buildNomField(),
                  const SizedBox(height: 16),
                  _buildEmailField(),
                  const SizedBox(height: 16),
                  _buildTelephoneAdresseFields(isSmallScreen),
                  const SizedBox(height: 16),
                  _buildPasswordFields(),
                  const SizedBox(height: 24),

                  // ✅ Bouton
                  _buildRegisterButton(isSmallScreen),
                  const SizedBox(height: 16),

                  // ✅ Lien connexion
                  _buildLoginLink(isSmallScreen),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 📌 HEADER
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
              'Créez votre compte agriculteur',
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

  // 📌 ERREUR
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

  // 📌 CHAMP TEXTE GÉNÉRIQUE
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

  // 📌 NOM
  Widget _buildNomField() {
    return _buildTextField(
      controller: _nomController,
      label: 'Nom complet',
      hint: 'tuekam jules',
      icon: Icons.person_outline,
      focusNode: _nomFocus,
      onSubmitted: (_) => _emailFocus.requestFocus(),
    );
  }

  // 📌 EMAIL
  Widget _buildEmailField() {
    return _buildTextField(
      controller: _emailController,
      label: 'Adresse email',
      hint: 'jules@tomscan.com',
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      focusNode: _emailFocus,
      onSubmitted: (_) => _telephoneFocus.requestFocus(),
    );
  }

  // 📌 TÉLÉPHONE + ADRESSE (responsive)
  Widget _buildTelephoneAdresseFields(bool isSmall) {
    if (isSmall) {
      return Column(
        children: [
          _buildTextField(
            controller: _telephoneController,
            label: 'Téléphone',
            hint: '691 234 567',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            focusNode: _telephoneFocus,
            onSubmitted: (_) => _adresseFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _adresseController,
            label: 'Adresse (optionnel)',
            hint: 'Douala, Cameroun',
            icon: Icons.location_on_outlined,
            focusNode: _adresseFocus,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildTextField(
            controller: _telephoneController,
            label: 'Téléphone',
            hint: '691 234 567',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            focusNode: _telephoneFocus,
            onSubmitted: (_) => _adresseFocus.requestFocus(),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 3,
          child: _buildTextField(
            controller: _adresseController,
            label: 'Adresse (optionnel)',
            hint: 'Douala, Cameroun',
            icon: Icons.location_on_outlined,
            focusNode: _adresseFocus,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
        ),
      ],
    );
  }

  // 📌 MOTS DE PASSE
  Widget _buildPasswordFields() {
    return Column(
      children: [
        _buildTextField(
          controller: _passwordController,
          label: 'Mot de passe',
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscureText: _obscurePassword,
          focusNode: _passwordFocus,
          onSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
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
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _confirmPasswordController,
          label: 'Confirmer le mot de passe',
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscureText: _obscureConfirmPassword,
          focusNode: _confirmPasswordFocus,
          onSubmitted: (_) => _register(),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppTheme.textLight,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }

  // 📌 BOUTON INSCRIPTION
  Widget _buildRegisterButton(bool isSmall) {
    return SizedBox(
      width: double.infinity,
      height: isSmall ? 48 : 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _register,
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
                    'S\'inscrire',
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

  // 📌 LIEN CONNEXION
  Widget _buildLoginLink(bool isSmall) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Déjà un compte ?',
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
                builder: (context) => const LoginScreen(),
              ),
            );
          },
          child: Text(
            'Se connecter',
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
  // 📌 INSCRIPTION AVEC INITIALISATION DU CACHE LOCAL
  // ============================================================
  Future<void> _register() async {
    // Validation
    if (_nomController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Veuillez entrer votre nom');
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Veuillez entrer votre email');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() =>
          _errorMessage = 'Le mot de passe doit faire au moins 6 caractères');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/auth/register',
        data: {
          'nom': _nomController.text.trim(),
          'email': _emailController.text.trim(),
          'mot_de_passe': _passwordController.text,
          'telephone': _telephoneController.text.trim(),
          'adresse': _adresseController.text.trim(),
          'role': 'agriculteur',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final userId = data['id_utilisateur'];
        final role = data['role'] ?? 'agriculteur';

        // ✅ Sauvegarder les données utilisateur
        await AuthService().saveUserData(
          token: data['token'],
          userId: userId,
          nom: data['nom'],
          email: data['email'],
          role: role,
        );

        // ✅ Initialiser le cache local avec l'ID utilisateur
        _db.setUserId(userId);
        debugPrint('📱 Cache local initialisé pour l\'utilisateur $userId');

        if (!mounted) return;

        // ✅ Rediriger vers l'accueil (après inscription, c'est un agriculteur)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage =
            e.response?.data['detail'] ?? 'Erreur lors de l\'inscription';
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

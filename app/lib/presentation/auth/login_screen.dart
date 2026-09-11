import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/cr_theme.dart';
import '../../data/remote/auth_service.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/local/auth_preferences.dart';
import '../widgets/cr_widgets.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _localAuth = LocalAuthentication();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _goHome(LoginResponseDto user) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
    );
  }

  Future<void> _checkSession() async {
    try {
      final session = await AuthPreferences.getSession();
      final biometric = await AuthPreferences.getBiometric();
      if (!mounted) return;
      setState(() {
        _hasSession = session['token'] != null && biometric;
      });
      if (_hasSession) _tryBiometricLogin();
    } catch (_) {}
  }

  Future<void> _tryBiometricLogin() async {
    final biometricEnabled = await AuthPreferences.getBiometric();
    if (!biometricEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa el acceso biométrico desde el menú')),
      );
      return;
    }

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return;

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Usa tu huella para ingresar',
      );

      if (!authenticated || !mounted) return;

      final session = await AuthPreferences.getSession();
      if (session['token'] == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesión cerrada. Ingresa con correo y contraseña para reactivar la huella.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      _goHome(
        LoginResponseDto(
          accessToken: session['token']!,
          tokenType: 'bearer',
          userId: session['userId'] ?? '',
          userName: session['userName'] ?? '',
          userRole: session['userRole'] ?? '',
          userEmail: session['userEmail'] ?? '',
        ),
      );
    } catch (_) {}
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final response = await _authService.login(
        _identifierController.text.trim(),
        _passwordController.text,
      );

      await AuthPreferences.saveSession(
        token: response.accessToken,
        userId: response.userId,
        userName: response.userName,
        userRole: response.userRole,
        userEmail: response.userEmail,
      );

      if (!mounted) return;
      _goHome(response);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: CR.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Campo con etiqueta superior (estilo Figma) ───────────────────────────
  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    required String hint,
    final String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    final t = CRTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.05,
                color: t.textSecondary),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(fontSize: 15, color: t.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: t.field,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 15),
            hintStyle: TextStyle(fontSize: 15, color: t.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: CR.mintDark, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: CR.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: CR.red, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Logo
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: CR.mint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Text(
                          'CR',
                          style: TextStyle(
                            color: CR.mintInk,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Carer-Record',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: t.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sistema de trazabilidad clínica',
                      style:
                          TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    Divider(height: 1, color: t.separator),
                    const SizedBox(height: 28),
                    // Título
                    Text(
                      'Iniciar sesión',
                      style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: t.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Accede con tus credenciales institucionales',
                      style:
                          TextStyle(fontSize: 14, color: t.textSecondary),
                    ),
                    const SizedBox(height: 26),
                    // Campos
                    _labeledField(
                      label: 'RUT o correo institucional',
                      controller: _identifierController,
                      hint: '12.345.678-9',
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Ingresa tu RUT o correo' : null,
                    ),
                    const SizedBox(height: 16),
                    _labeledField(
                      label: 'Contraseña',
                      controller: _passwordController,
                      hint: '••••••••',
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: t.textTertiary,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
                    ),
                    const SizedBox(height: 22),
                    // CTA
                    _isLoading
                        ? const SizedBox(
                            height: 32,
                            child: CircularProgressIndicator(color: CR.mintDark),
                          )
                        : CRPrimaryButton(
                            label: 'Iniciar sesión',
                            onPressed: _handleLogin,
                          ),
                    const SizedBox(height: 18),
                    // Opción biométrica
                    if (_hasSession)
                      InkWell(
                        onTap: _tryBiometricLogin,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fingerprint, size: 22, color: CR.blue),
                              const SizedBox(width: 8),
                              const Text(
                                'Acceder con huella',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: CR.blue),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    Text(
                      'Uso exclusivo personal clínico autorizado',
                      style: TextStyle(fontSize: 12, color: t.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

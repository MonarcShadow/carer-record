import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme.dart';
import '../../data/remote/auth_service.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/local/auth_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController  = TextEditingController();
  final _authService         = AuthService();
  final _localAuth           = LocalAuthentication();

  bool _obscurePassword = true;
  bool _isLoading       = false;
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

  Future<void> _checkSession() async {
  final session = await AuthPreferences.getSession();
  final biometric = await AuthPreferences.getBiometric();
  setState(() {
    _hasSession = session['token'] != null && biometric;
  });
  if (_hasSession) _tryBiometricLogin();
}

  Future<void> _tryBiometricLogin() async {
    final biometricEnabled = await AuthPreferences.getBiometric();
    if (!biometricEnabled) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inicia sesión con correo y contraseña la primera vez'),
          ),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            user: LoginResponseDto(
              accessToken: session['token']!,
              tokenType:   'bearer',
              userName:    session['userName'] ?? '',
              userRole:    session['userRole'] ?? '',
              userEmail:   session['userEmail'] ?? '',
            ),
          ),
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
        token:     response.accessToken,
        userName:  response.userName,
        userRole:  response.userRole,
        userEmail: _identifierController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(user: response)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text(
                      'CR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Carer-Record',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Acceso institucional asistencial',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 48),
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'RUT o correo institucional',
                    hintText: '12.345.678-9',
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Ingresa tu RUT o correo' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
                ),
                const SizedBox(height: 28),
                _isLoading
                    ? const CircularProgressIndicator(color: AppTheme.primary)
                    : ElevatedButton(
                        onPressed: _handleLogin,
                        child: const Text('Ingresar al sistema'),
                      ),
                const SizedBox(height: 24),
                if (_hasSession)
                  TextButton.icon(
                    onPressed: _tryBiometricLogin,
                    icon: const Icon(Icons.fingerprint,
                        color: AppTheme.textSecondary),
                    label: const Text(
                      'Acceso biométrico disponible',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
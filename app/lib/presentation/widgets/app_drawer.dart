import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme/cr_theme.dart';
import '../../data/local/auth_preferences.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../auth/login_screen.dart';
import '../settings/ai_settings_screen.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme_provider.dart';

class AppDrawer extends StatefulWidget {
  final LoginResponseDto user;

  const AppDrawer({super.key, required this.user});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _biometricEnabled = false;
  bool _hasBiometrics    = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkBiometrics();
  }

  Future<void> _loadPreferences() async {
    final biometric = await AuthPreferences.getBiometric();
    setState(() {
      _biometricEnabled = biometric;
    });
  }

  Future<void> _checkBiometrics() async {
    try {
      final available = await _localAuth.canCheckBiometrics;
      final enrolled  = await _localAuth.isDeviceSupported();
      setState(() => _hasBiometrics = available && enrolled);
    } catch (_) {
      setState(() => _hasBiometrics = false);
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value && _hasBiometrics) {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Registra tu huella para iniciar sesión más rápido',
      );
      if (!authenticated) return;
    }
    await AuthPreferences.setBiometric(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _logout() async {
    await AuthPreferences.clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'CR';
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':  return 'Administrador del Sistema';
      case 'doctor': return 'Médico';
      case 'nurse':  return 'Enfermería';
      case 'tech':   return 'Equipo Ampliado';
      default:       return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Drawer(
      backgroundColor: t.background,
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [CR.mintDark, CR.mint],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      _initials(widget.user.userName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.user.userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _roleLabel(widget.user.userRole),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Huella dactilar
            ListTile(
              leading: Icon(
                Icons.fingerprint,
                color: t.isDark ? CR.mint : CR.mintDark,
              ),
              title: Text(
                'Inicio con huella',
                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                _hasBiometrics
                    ? 'Tu dispositivo es compatible'
                    : 'Tu dispositivo no tiene lector',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
              trailing: Switch(
                value: _biometricEnabled,
                activeThumbColor: CR.mint,
                activeTrackColor: CR.mintDark.withValues(alpha: 0.35),
                onChanged: _hasBiometrics ? _toggleBiometric : null,
              ),
            ),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: t.separator,
            ),

            ListTile(
              leading: Icon(
                Icons.psychology,
                color: t.isDark ? CR.mint : CR.mintDark,
              ),
              title: Text(
                'Configuración de IA',
                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context); // cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                );
              },
            ),

            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: t.separator,
            ),

            // Modo oscuro
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) => ListTile(
                leading: Icon(
                  themeProvider.isDark ? Icons.light_mode : Icons.dark_mode,
                  color: t.isDark ? CR.mint : CR.mintDark,
                ),
                title: Text(
                  'Modo oscuro',
                  style: TextStyle(
                      color: t.textPrimary, fontWeight: FontWeight.w500),
                ),
                trailing: Switch(
                  value: themeProvider.isDark,
                  activeThumbColor: CR.mint,
                  activeTrackColor: CR.mintDark.withValues(alpha: 0.35),
                  onChanged: (_) => themeProvider.toggle(),
                ),
              ),
            ),

            const Spacer(),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: t.separator,
            ),

            // Cerrar sesión
            ListTile(
              leading: const Icon(Icons.logout, color: CR.red),
              title: const Text('Cerrar sesión',
                  style: TextStyle(color: CR.red, fontWeight: FontWeight.w500)),
              onTap: _logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
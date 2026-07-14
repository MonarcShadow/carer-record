import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme.dart';
import '../../data/local/auth_preferences.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../auth/login_screen.dart';

class AppDrawer extends StatefulWidget {
  final LoginResponseDto user;

  const AppDrawer({super.key, required this.user});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _biometricEnabled = false;
  bool _darkMode         = false;
  bool _hasBiometrics    = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkBiometrics();
  }

  Future<void> _loadPreferences() async {
    final biometric = await AuthPreferences.getBiometric();
    final darkMode  = await AuthPreferences.getDarkMode();
    setState(() {
      _biometricEnabled = biometric;
      _darkMode         = darkMode;
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
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              color: AppTheme.primary,
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
              leading: const Icon(Icons.fingerprint, color: AppTheme.primary),
              title: const Text('Inicio con huella'),
              subtitle: Text(
                _hasBiometrics
                    ? 'Tu dispositivo es compatible'
                    : 'Tu dispositivo no tiene lector',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Switch(
                value: _biometricEnabled,
                activeThumbColor: AppTheme.primary,
                onChanged: _hasBiometrics ? _toggleBiometric : null,
              ),
            ),

            const Divider(indent: 16, endIndent: 16),

            // Modo oscuro
            ListTile(
              leading: const Icon(Icons.dark_mode, color: AppTheme.primary),
              title: const Text('Modo oscuro'),
              subtitle: const Text('Próximamente', style: TextStyle(fontSize: 12)),
              trailing: Switch(
                value: _darkMode,
                activeThumbColor: AppTheme.primary,
                onChanged: (value) async {
                  await AuthPreferences.setDarkMode(value);
                  setState(() => _darkMode = value);
                },
              ),
            ),

            const Spacer(),
            const Divider(indent: 16, endIndent: 16),

            // Cerrar sesión
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Cerrar sesión',
                  style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
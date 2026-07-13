import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme.dart';
import '../../data/local/auth_preferences.dart';
import '../../data/remote/dto/auth_dto.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final LoginResponseDto user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
        // En esta versión, los parámetros van directamente aquí:
        biometricOnly: true,
      );
      if (!authenticated) return;
    }
    await AuthPreferences.setBiometric(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _logout() async {
    // No borramos toda la sesión para permitir reingreso con huella
    // Solo navegamos al login
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Carer Record'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: _buildDrawer(),
      body: _buildAdminPanel(),
    );
  }

  // ── Drawer lateral ──────────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera del drawer
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
              subtitle: const Text(
                'Próximamente',
                style: TextStyle(fontSize: 12),
              ),
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

  // ── Panel principal Admin ───────────────────────────────────────────────────

  Widget _buildAdminPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Avatar con iniciales
          CircleAvatar(
            radius: 48,
            backgroundColor: AppTheme.primary,
            child: Text(
              _initials(widget.user.userName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Nombre y rol
          Text(
            widget.user.userName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _roleLabel(widget.user.userRole),
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Email
          Text(
            widget.user.userEmail ?? '',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 32),

          // Grid de acciones
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _ActionCard(
                icon: Icons.person_add,
                label: 'Agregar médico',
                onTap: () {},
              ),
              _ActionCard(
                icon: Icons.people,
                label: 'Gestionar usuarios',
                onTap: () {},
              ),
              _ActionCard(
                icon: Icons.local_hospital,
                label: 'Pacientes',
                onTap: () {},
              ),
              _ActionCard(
                icon: Icons.bar_chart,
                label: 'Estadísticas',
                onTap: () {},
              ),
              _ActionCard(
                icon: Icons.settings,
                label: 'Configuración',
                onTap: () {},
              ),
              _ActionCard(
                icon: Icons.mic,
                label: 'Comando de voz',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Widget tarjeta de acción ────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../admin/users_screen.dart';
import '../admin/user_form_screen.dart';
import '../../core/theme/theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../widgets/app_drawer.dart';
import '../admin/patients_screen.dart';

class HomeScreen extends StatefulWidget {
  final LoginResponseDto user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'CR';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme   = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carer Record'),
      ),
      drawer: AppDrawer(user: widget.user),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
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
            Text(
              widget.user.userName,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Administrador del Sistema',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.user.userEmail,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 32),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _ActionCard(icon: Icons.person_add,     label: 'Agregar médico',
                  onTap: () async => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const UserFormScreen()))),
                _ActionCard(icon: Icons.people,         label: 'Gestionar usuarios',
                  onTap: () async => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const UsersScreen()))),
                _ActionCard(icon: Icons.local_hospital, label: 'Pacientes',
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PatientsScreen()),),),
                _ActionCard(icon: Icons.bar_chart,      label: 'Estadísticas',  onTap: () {}),
                _ActionCard(icon: Icons.settings,       label: 'Configuración', onTap: () {}),
                _ActionCard(icon: Icons.mic,            label: 'Comando de voz',onTap: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.7)
                  : Colors.black.withValues(alpha: 0.14),
              blurRadius: isDark ? 18 : 10,
              spreadRadius: isDark ? 0.5 : 0,
              offset: const Offset(0, 2),
            ),
            if (isDark)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, -1),
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
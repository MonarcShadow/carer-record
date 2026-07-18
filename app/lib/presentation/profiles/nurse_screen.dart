import 'package:flutter/material.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../widgets/app_drawer.dart';

class NurseScreen extends StatelessWidget {
  final LoginResponseDto user;
  const NurseScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Se eliminó backgroundColor fijo
      appBar: AppBar(
        title: const Text('Carer Record'),
        // Se eliminaron backgroundColor, foregroundColor y elevation fijos
      ),
      drawer: AppDrawer(user: user),
      body: _buildPanel(context),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _avatar(context), // Pasamos el context para acceder al tema
          const SizedBox(height: 16),
          _userName(context), // Pasamos el context para acceder al tema
          const SizedBox(height: 32),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _ActionCard(icon: Icons.local_hospital,   label: 'Pacientes del área', onTap: () {}),
              _ActionCard(icon: Icons.assignment,       label: 'Registrar seguimiento', onTap: () {}),
              _ActionCard(icon: Icons.swap_horiz,       label: 'Cambio de turno',    onTap: () {}),
              _ActionCard(icon: Icons.notifications,    label: 'Alertas',            onTap: () {}),
              _ActionCard(icon: Icons.mic,              label: 'Comando de voz',     onTap: () {}),
              _ActionCard(icon: Icons.bar_chart,        label: 'Reportes',           onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final theme = Theme.of(context);
    final parts = user.userName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : user.userName.isNotEmpty ? user.userName[0].toUpperCase() : 'EN';

    return CircleAvatar(
      radius: 48,
      backgroundColor: theme.colorScheme.primary,
      child: Text(
        initials,
        style: TextStyle(
          color: theme.colorScheme.onPrimary, 
          fontSize: 36, 
          fontWeight: FontWeight.bold
        ),
      ),
    );
  }

  Widget _userName(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          user.userName,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Enfermería',
            style: TextStyle(
              color: theme.colorScheme.primary, 
              fontWeight: FontWeight.w600, 
              fontSize: 13
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          user.userEmail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodySmall?.color
          )
        ),
      ],
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.12),
              blurRadius: isDark ? 18 : 8,
              offset: const Offset(0, 2),
            ),
            if (isDark)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.06),
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
                color: theme.colorScheme.primary.withValues(alpha: 0.1), 
                shape: BoxShape.circle
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)
            ),
          ],
        ),
      ),
    );
  }
}
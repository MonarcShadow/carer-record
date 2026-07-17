import 'package:flutter/material.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../widgets/app_drawer.dart';

class DoctorScreen extends StatelessWidget {
  final LoginResponseDto user;
  const DoctorScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Se eliminó backgroundColor: AppTheme.background
      appBar: AppBar(
        title: const Text('Carer Record'),
        // Se eliminaron colores y elevación fijos
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
          _avatar(context), // Pasamos el context
          const SizedBox(height: 16),
          _userName(context), // Pasamos el context
          const SizedBox(height: 32),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _ActionCard(icon: Icons.people,           label: 'Mis pacientes',    onTap: () {}),
              _ActionCard(icon: Icons.note_alt,         label: 'Notas de turno',   onTap: () {}),
              _ActionCard(icon: Icons.swap_horiz,       label: 'Cambio de turno',  onTap: () {}),
              _ActionCard(icon: Icons.history,          label: 'Historial clínico',onTap: () {}),
              _ActionCard(icon: Icons.mic,              label: 'Comando de voz',   onTap: () {}),
              _ActionCard(icon: Icons.notifications,    label: 'Alertas',          onTap: () {}),
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
        : user.userName.isNotEmpty ? user.userName[0].toUpperCase() : 'DR';
        
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
            'Médico',
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
            color: theme.textTheme.bodySmall?.color // Usa el color secundario de texto del tema
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
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor, // Reemplaza Colors.white
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.06), // Reemplaza Colors.black
              blurRadius: 8, 
              offset: const Offset(0, 2)
            )
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
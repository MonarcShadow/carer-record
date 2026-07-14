import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../widgets/app_drawer.dart';

class NurseScreen extends StatelessWidget {
  final LoginResponseDto user;
  const NurseScreen({super.key, required this.user});

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
          _avatar(),
          const SizedBox(height: 16),
          _userName(),
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

  Widget _avatar() {
    final parts = user.userName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : user.userName[0].toUpperCase();
    return CircleAvatar(
      radius: 48,
      backgroundColor: AppTheme.primary,
      child: Text(initials,
          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
    );
  }

  Widget _userName() {
    return Column(
      children: [
        Text(user.userName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Enfermería',
              style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        const SizedBox(height: 8),
        Text(user.userEmail,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}
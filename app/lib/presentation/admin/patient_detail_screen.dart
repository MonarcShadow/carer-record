import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../data/remote/patients_service.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final String patientName; // para el AppBar mientras carga

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final PatientsService _service = PatientsService();
  PatientDetailModel? _patient;
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await _service.getPatientById(widget.patientId);
      setState(() { _patient = p; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Helpers de presentación ────────────────────────────────────────────────

  String _initials(PatientDetailModel p) {
    final f = p.firstName.trim();
    final l = p.lastName.trim();
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    if (f.isNotEmpty) return f[0].toUpperCase();
    return '?';
  }

  String _genderLabel(String g) {
    switch (g.toLowerCase()) {
      case 'male':   return 'Masculino';
      case 'female': return 'Femenino';
      case 'other':  return 'Otro';
      default:       return 'Desconocido';
    }
  }

  String _maritalLabel(String m) {
    switch (m.toLowerCase()) {
      case 'married':   return 'Casado/a';
      case 'single':    return 'Soltero/a';
      case 'divorced':  return 'Divorciado/a';
      case 'widowed':   return 'Viudo/a';
      default:          return m.isEmpty ? '—' : m;
    }
  }

  String _sourceLabel(String s) {
    switch (s) {
      case 'fhir':   return 'FHIR R4';
      case 'hl7v2':  return 'HL7 v2';
      case 'csv':    return 'CSV';
      case 'manual': return 'Manual';
      default:       return s;
    }
  }

  // Formatea "2024-01-15T08:30:00" → "15/01/2024  08:30"
  // y "2024-01-15" → "15/01/2024"
  String _fmt(String raw) {
    if (raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      final date = '${dt.day.toString().padLeft(2,'0')}/'
                   '${dt.month.toString().padLeft(2,'0')}/'
                   '${dt.year}';
      if (raw.contains('T') || raw.contains(' ')) {
        final time = '${dt.hour.toString().padLeft(2,'0')}:'
                     '${dt.minute.toString().padLeft(2,'0')}';
        return '$date  $time';
      }
      return date;
    } catch (_) {
      return raw;
    }
  }

  String _val(String v) => v.isEmpty ? '—' : v;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_patient?.fullName ?? widget.patientName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _buildContent(_patient!, theme, isDark),
    );
  }

  Widget _buildContent(
      PatientDetailModel p, ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p, theme, isDark),
          const SizedBox(height: 20),
          _buildSection(
            theme: theme,
            isDark: isDark,
            icon: Icons.local_hospital,
            title: 'Hospitalización',
            rows: [
              _InfoRow('Zona',              _val(p.ward)),
              _InfoRow('Cama',              _val(p.bedNumber)),
              _InfoRow('Ingreso',           _fmt(p.admissionDate)),
              _InfoRow('Alta esperada',     _fmt(p.expectedDischargeDate)),
              _InfoRow('Diagnóstico',       _val(p.primaryDiagnosis),
                  multiline: true),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            theme: theme,
            isDark: isDark,
            icon: Icons.person,
            title: 'Datos personales',
            rows: [
              _InfoRow('Nombre completo',   p.fullName),
              _InfoRow('Fecha nacimiento',  _fmt(p.birthDate)),
              _InfoRow('Género',            _genderLabel(p.gender)),
              _InfoRow('Estado civil',      _maritalLabel(p.maritalStatus)),
              _InfoRow('Teléfono',          _val(p.phone)),
              _InfoRow('Dirección',         _val(p.address), multiline: true),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            theme: theme,
            isDark: isDark,
            icon: Icons.language,
            title: 'Información adicional',
            rows: [
              _InfoRow('Idioma',        _val(p.language)),
              _InfoRow('Etnia',         _val(p.ethnicity)),
              _InfoRow('Origen datos',  _sourceLabel(p.sourceSystem)),
              _InfoRow('Registrado',    _fmt(p.createdAt)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Header con avatar y badge de zona ─────────────────────────────────────
  Widget _buildHeader(
      PatientDetailModel p, ThemeData theme, bool isDark) {
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
          child: Text(
            _initials(p),
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          p.fullName,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        if (p.ward.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              p.ward,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  // ── Tarjeta de sección ─────────────────────────────────────────────────────
  Widget _buildSection({
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required String title,
    required List<_InfoRow> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.08), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.07),
            blurRadius: isDark ? 0 : 8,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado de sección
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Filas de datos
          ...rows.map((row) => _buildRow(row, theme)),
        ],
      ),
    );
  }

  Widget _buildRow(_InfoRow row, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: row.multiline
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  row.value,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    row.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Modelo interno para filas ──────────────────────────────────────────────────
class _InfoRow {
  final String label;
  final String value;
  final bool   multiline;
  const _InfoRow(this.label, this.value, {this.multiline = false});
}
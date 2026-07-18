import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../data/remote/patients_service.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

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

  // Estado de expansión por sección
  final Map<String, bool> _expanded = {
    'hospitalizacion': true,   // abierta por defecto
    'personal':        false,
    'encuentros':      false,
    'condiciones':     false,
    'medicamentos':    false,
    'observaciones':   false,
    'alergias':        false,
    'adicional':       false,
  };

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

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _initials(PatientDetailModel p) {
    final f = p.firstName.trim();
    final l = p.lastName.trim();
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    return f.isNotEmpty ? f[0].toUpperCase() : '?';
  }

  String _fmt(String raw) {
    if (raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      final d = '${dt.day.toString().padLeft(2,'0')}/'
                '${dt.month.toString().padLeft(2,'0')}/'
                '${dt.year}';
      if (raw.contains('T') || raw.contains(' ')) {
        final t = '${dt.hour.toString().padLeft(2,'0')}:'
                  '${dt.minute.toString().padLeft(2,'0')}';
        return '$d  $t';
      }
      return d;
    } catch (_) { return raw; }
  }

  String _val(String v) => v.isEmpty ? '—' : v;

  String _genderLabel(String g) => switch (g.toLowerCase()) {
    'male'   => 'Masculino',
    'female' => 'Femenino',
    'other'  => 'Otro',
    _        => 'Desconocido',
  };

  String _maritalLabel(String m) => switch (m.toLowerCase()) {
    'married'  => 'Casado/a',
    'single'   => 'Soltero/a',
    'divorced' => 'Divorciado/a',
    'widowed'  => 'Viudo/a',
    _          => m.isEmpty ? '—' : m,
  };

  String _sourceLabel(String s) => switch (s) {
    'fhir'   => 'FHIR R4',
    'hl7v2'  => 'HL7 v2',
    'csv'    => 'CSV',
    'manual' => 'Manual',
    _        => s,
  };

  Color _severityColor(String s) => switch (s.toLowerCase()) {
    'severe' || 'high'   => Colors.red,
    'moderate' || 'medium' => Colors.orange,
    'mild' || 'low'      => Colors.amber,
    _                    => Colors.grey,
  };

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_patient?.fullName ?? widget.patientName),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : _buildContent(_patient!, theme, isDark),
    );
  }

  Widget _buildError(ThemeData theme) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );

  Widget _buildContent(PatientDetailModel p, ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p, theme),
          const SizedBox(height: 20),

          // Hospitalización
          _CollapsibleSection(
            key: const ValueKey('hospitalizacion'),
            icon: Icons.local_hospital,
            title: 'Hospitalización',
            isDark: isDark,
            isExpanded: _expanded['hospitalizacion']!,
            onToggle: () => setState(
                () => _expanded['hospitalizacion'] = !_expanded['hospitalizacion']!),
            child: Column(children: [
              _row(theme, 'Zona',           _val(p.ward)),
              _row(theme, 'Cama',           _val(p.bedNumber)),
              _row(theme, 'Ingreso',        _fmt(p.admissionDate)),
              _row(theme, 'Alta esperada',  _fmt(p.expectedDischargeDate)),
              _rowMulti(theme, 'Diagnóstico principal', _val(p.primaryDiagnosis)),
            ]),
          ),
          const SizedBox(height: 12),

          // Datos personales
          _CollapsibleSection(
            key: const ValueKey('personal'),
            icon: Icons.person,
            title: 'Datos personales',
            isDark: isDark,
            isExpanded: _expanded['personal']!,
            onToggle: () => setState(
                () => _expanded['personal'] = !_expanded['personal']!),
            child: Column(children: [
              _row(theme, 'Nombre',          p.fullName),
              _row(theme, 'Nacimiento',      _fmt(p.birthDate)),
              _row(theme, 'Género',          _genderLabel(p.gender)),
              _row(theme, 'Estado civil',    _maritalLabel(p.maritalStatus)),
              _row(theme, 'Teléfono',        _val(p.phone)),
              _row(theme, 'Idioma',          _val(p.language)),
              _row(theme, 'Etnia',           _val(p.ethnicity)),
              _rowMulti(theme, 'Dirección',  _val(p.address)),
            ]),
          ),
          const SizedBox(height: 12),

          // Encuentros clínicos
          _CollapsibleSection(
            key: const ValueKey('encuentros'),
            icon: Icons.medical_services,
            title: 'Encuentros clínicos',
            badge: p.encounters.length,
            isDark: isDark,
            isExpanded: _expanded['encuentros']!,
            onToggle: () => setState(
                () => _expanded['encuentros'] = !_expanded['encuentros']!),
            child: p.encounters.isEmpty
                ? _empty(theme, 'Sin encuentros registrados')
                : Column(
                    children: p.encounters.asMap().entries.map((e) {
                      final enc = e.value;
                      return _subCard(theme, isDark,
                        title: _val(enc.type),
                        items: [
                          _row(theme, 'Estado',    _val(enc.status)),
                          _row(theme, 'Clase',     _val(enc.encounterClass)),
                          _row(theme, 'Inicio',    _fmt(enc.startDate)),
                          _row(theme, 'Fin',       _fmt(enc.endDate)),
                          _row(theme, 'Médico',    _val(enc.practitioner)),
                          _rowMulti(theme, 'Motivo',   _val(enc.reason)),
                          if (enc.referralReason.isNotEmpty)
                            _rowMulti(theme, 'Derivación', enc.referralReason),
                        ],
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // Condiciones
          _CollapsibleSection(
            key: const ValueKey('condiciones'),
            icon: Icons.healing,
            title: 'Condiciones',
            badge: p.conditions.length,
            isDark: isDark,
            isExpanded: _expanded['condiciones']!,
            onToggle: () => setState(
                () => _expanded['condiciones'] = !_expanded['condiciones']!),
            child: p.conditions.isEmpty
                ? _empty(theme, 'Sin condiciones registradas')
                : Column(
                    children: p.conditions.map((c) => _subCard(theme, isDark,
                      title: _val(c.description),
                      severityColor: c.severity.isNotEmpty
                          ? _severityColor(c.severity) : null,
                      items: [
                        _row(theme, 'Estado',    _val(c.status)),
                        _row(theme, 'Severidad', _val(c.severity)),
                        _row(theme, 'Inicio',    _fmt(c.onsetDate)),
                        _row(theme, 'Resolución',_fmt(c.abatementDate)),
                        _row(theme, 'Registrado por', _val(c.recordedBy)),
                      ],
                    )).toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // Medicamentos
          _CollapsibleSection(
            key: const ValueKey('medicamentos'),
            icon: Icons.medication,
            title: 'Medicamentos',
            badge: p.medications.length,
            isDark: isDark,
            isExpanded: _expanded['medicamentos']!,
            onToggle: () => setState(
                () => _expanded['medicamentos'] = !_expanded['medicamentos']!),
            child: p.medications.isEmpty
                ? _empty(theme, 'Sin medicamentos registrados')
                : Column(
                    children: p.medications.map((m) => _subCard(theme, isDark,
                      title: _val(m.description),
                      items: [
                        _row(theme, 'Estado',    _val(m.status)),
                        _row(theme, 'Dosis',     _val(m.dosage)),
                        _row(theme, 'Frecuencia',_val(m.frequency)),
                        _row(theme, 'Prescriptor',_val(m.prescriber)),
                        _row(theme, 'Inicio',    _fmt(m.startDate)),
                        _row(theme, 'Fin',       _fmt(m.endDate)),
                        if (m.instructions.isNotEmpty)
                          _rowMulti(theme, 'Instrucciones', m.instructions),
                      ],
                    )).toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // Observaciones
          _CollapsibleSection(
            key: const ValueKey('observaciones'),
            icon: Icons.monitor_heart,
            title: 'Observaciones',
            badge: p.observations.length,
            isDark: isDark,
            isExpanded: _expanded['observaciones']!,
            onToggle: () => setState(
                () => _expanded['observaciones'] = !_expanded['observaciones']!),
            child: p.observations.isEmpty
                ? _empty(theme, 'Sin observaciones registradas')
                : Column(
                    children: p.observations.map((o) {
                      final valueStr = [
                        if (o.value.isNotEmpty) o.value,
                        if (o.unit.isNotEmpty) o.unit,
                      ].join(' ');
                      final rangeStr = (o.valueLow.isNotEmpty || o.valueHigh.isNotEmpty)
                          ? '${o.valueLow} – ${o.valueHigh} ${o.unit}'.trim()
                          : '';
                      return _subCard(theme, isDark,
                        title: _val(o.description),
                        items: [
                          _row(theme, 'Categoría',     _val(o.category)),
                          _row(theme, 'Valor',         valueStr.isEmpty ? '—' : valueStr),
                          if (rangeStr.isNotEmpty)
                            _row(theme, 'Rango normal', rangeStr),
                          _row(theme, 'Interpretación',_val(o.interpretation)),
                          _row(theme, 'Estado',        _val(o.status)),
                          _row(theme, 'Fecha',         _fmt(o.effectiveDate)),
                        ],
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // Alergias
          _CollapsibleSection(
            key: const ValueKey('alergias'),
            icon: Icons.warning_amber_rounded,
            title: 'Alergias',
            badge: p.allergies.length,
            isDark: isDark,
            isExpanded: _expanded['alergias']!,
            onToggle: () => setState(
                () => _expanded['alergias'] = !_expanded['alergias']!),
            child: p.allergies.isEmpty
                ? _empty(theme, 'Sin alergias registradas')
                : Column(
                    children: p.allergies.map((a) => _subCard(theme, isDark,
                      title: _val(a.description),
                      severityColor: a.severity.isNotEmpty
                          ? _severityColor(a.severity) : null,
                      items: [
                        _row(theme, 'Estado',           _val(a.status)),
                        _row(theme, 'Severidad',        _val(a.severity)),
                        _row(theme, 'Inicio',           _fmt(a.onsetDate)),
                        _row(theme, 'Última ocurrencia',_fmt(a.lastOccurrence)),
                        _row(theme, 'Registrado por',   _val(a.recordedBy)),
                        if (a.reaction.isNotEmpty)
                          _rowMulti(theme, 'Reacción', a.reaction),
                      ],
                    )).toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // Información adicional
          _CollapsibleSection(
            key: const ValueKey('adicional'),
            icon: Icons.info_outline,
            title: 'Información adicional',
            isDark: isDark,
            isExpanded: _expanded['adicional']!,
            onToggle: () => setState(
                () => _expanded['adicional'] = !_expanded['adicional']!),
            child: Column(children: [
              _row(theme, 'Origen datos', _sourceLabel(p.sourceSystem)),
              _row(theme, 'Registrado',   _fmt(p.createdAt)),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(PatientDetailModel p, ThemeData theme) => Column(
    children: [
      CircleAvatar(
        radius: 44,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
        child: Text(_initials(p),
            style: const TextStyle(color: AppTheme.primary,
                fontSize: 34, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 12),
      Text(p.fullName,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
      const SizedBox(height: 6),
      if (p.ward.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(p.ward,
              style: const TextStyle(color: AppTheme.primary,
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ),
    ],
  );

  // ── Helpers de fila ────────────────────────────────────────────────────────
  Widget _row(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );

  Widget _rowMulti(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color
                    ?.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    ),
  );

  Widget _empty(ThemeData theme, String msg) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Text(msg,
        style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5))),
  );

  // Sub-tarjeta para items dentro de listas (encuentros, condiciones…)
  Widget _subCard(ThemeData theme, bool isDark, {
    required String title,
    required List<Widget> items,
    Color? severityColor,
  }) =>
      Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : AppTheme.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: severityColor?.withValues(alpha: 0.4) ??
                AppTheme.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  if (severityColor != null) ...[
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: severityColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...items,
          ],
        ),
      );
}

// ── Widget colapsable reutilizable ─────────────────────────────────────────────
class _CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String   title;
  final int?     badge;
  final bool     isDark;
  final bool     isExpanded;
  final VoidCallback onToggle;
  final Widget   child;

  const _CollapsibleSection({
    super.key,
    required this.icon,
    required this.title,
    this.badge,
    required this.isDark,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
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
              blurRadius: 12, spreadRadius: 1,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: Column(
        children: [
          // Encabezado siempre visible
          InkWell(
            onTap: onToggle,
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
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
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary)),
                  ),
                  // Badge con cantidad
                  if (badge != null && badge! > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$badge',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        color: AppTheme.primary.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
          // Contenido animado
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(children: [
              const Divider(height: 1),
              const SizedBox(height: 4),
              child,
              const SizedBox(height: 8),
            ]),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}
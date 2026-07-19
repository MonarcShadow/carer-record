import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/remote/patients_service.dart';
import 'notes_screen.dart';

// ── Configuración de cada sección ─────────────────────────────────────────────
class _SectionConfig {
  final IconData icon;
  final String   title;
  // Mapeo campo_db → etiqueta en español. null = ocultar el campo.
  final Map<String, String?> fields;
  // Campo a usar como título de cada sub-tarjeta
  final String? cardTitle;
  // Campos que deben mostrarse en multilinea
  final Set<String> multiline;
  // Color de severidad basado en este campo
  final String? severityField;

  const _SectionConfig({
    required this.icon,
    required this.title,
    required this.fields,
    this.cardTitle,
    this.multiline = const {},
    this.severityField,
  });
}

const _sectionConfigs = <String, _SectionConfig>{
  'encounters': _SectionConfig(
    icon: Icons.medical_services,
    title: 'Encuentros clínicos',
    cardTitle: 'encounter_type',
    fields: {
      'encounter_type':   'Tipo',
      'status':           'Estado',
      'encounter_class':  'Clase',
      'start_date':       'Inicio',
      'end_date':         'Fin',
      'practitioner_name':'Médico',
      'reason':           'Motivo',
      'referral_reason':  'Derivación',
    },
    multiline: {'reason', 'referral_reason'},
  ),
  'conditions': _SectionConfig(
    icon: Icons.healing,
    title: 'Condiciones',
    cardTitle: 'description',
    severityField: 'severity',
    fields: {
      'description':    null,       // ya es el título
      'status':         'Estado',
      'severity':       'Severidad',
      'onset_date':     'Inicio',
      'abatement_date': 'Resolución',
      'recorded_by':    'Registrado por',
    },
  ),
  'medications': _SectionConfig(
    icon: Icons.medication,
    title: 'Medicamentos',
    cardTitle: 'description',
    fields: {
      'description':  null,
      'status':       'Estado',
      'dosage':       'Dosis',
      'frequency':    'Frecuencia',
      'prescriber':   'Prescriptor',
      'start_date':   'Inicio',
      'end_date':     'Fin',
      'instructions': 'Instrucciones',
    },
    multiline: {'instructions'},
  ),
  'observations': _SectionConfig(
    icon: Icons.monitor_heart,
    title: 'Observaciones',
    cardTitle: 'description',
    fields: {
      'description':    null,
      'category':       'Categoría',
      'value':          'Valor',
      'unit':           null,       // se combina con value
      'value_low':      'Rango mín.',
      'value_high':     'Rango máx.',
      'interpretation': 'Interpretación',
      'status':         'Estado',
      'effective_date': 'Fecha',
    },
  ),
  'allergies': _SectionConfig(
    icon: Icons.warning_amber_rounded,
    title: 'Alergias',
    cardTitle: 'description',
    severityField: 'severity',
    fields: {
      'description':     null,
      'status':          'Estado',
      'severity':        'Severidad',
      'onset_date':      'Inicio',
      'last_occurrence': 'Última ocurrencia',
      'reaction':        'Reacción',
      'recorded_by':     'Registrado por',
    },
    multiline: {'reaction'},
  ),
  'procedures': _SectionConfig(
    icon: Icons.local_hospital,
    title: 'Procedimientos',
    cardTitle: 'description',
    fields: {
      'description':    null,
      'status':         'Estado',
      'performed_date': 'Realizado',
      'performer':      'Realizado por',
      'body_site':      'Sitio',
      'reason':         'Motivo',
    },
    multiline: {'reason'},
  ),
  'immunizations': _SectionConfig(
    icon: Icons.vaccines,
    title: 'Inmunizaciones',
    cardTitle: 'description',
    fields: {
      'description':     null,
      'status':          'Estado',
      'occurrence_date': 'Fecha',
      'manufacturer':    'Fabricante',
      'lot_number':      'Lote',
      'site':            'Sitio',
      'route':           'Vía',
      'performer':       'Aplicado por',
    },
  ),
  'diagnostic_reports': _SectionConfig(
    icon: Icons.assignment,
    title: 'Informes diagnósticos',
    cardTitle: 'description',
    fields: {
      'description':    null,
      'category':       'Categoría',
      'status':         'Estado',
      'effective_date': 'Fecha muestra',
      'issued_date':    'Emitido',
      'performer':      'Realizado por',
      'conclusion':     'Conclusión',
    },
    multiline: {'conclusion'},
  ),
  'imaging_studies': _SectionConfig(
    icon: Icons.image_search,
    title: 'Estudios de imagen',
    cardTitle: 'description',
    fields: {
      'description':      null,
      'modality':         'Modalidad',
      'status':           'Estado',
      'started_date':     'Fecha',
      'body_site':        'Sitio',
      'number_series':    'Series',
      'number_instances': 'Instancias',
      'referrer':         'Derivado por',
    },
  ),
  'devices': _SectionConfig(
    icon: Icons.devices,
    title: 'Dispositivos',
    cardTitle: 'description',
    fields: {
      'description':    null,
      'status':         'Estado',
      'manufacturer':   'Fabricante',
      'model':          'Modelo',
      'lot_number':     'Lote',
      'serial_number':  'Nº serie',
      'expiration_date':'Vencimiento',
      'udi':            'UDI',
    },
  ),
  'care_plans': _SectionConfig(
    icon: Icons.fact_check,
    title: 'Planes de cuidado',
    cardTitle: 'title',
    fields: {
      'title':       null,
      'status':      'Estado',
      'intent':      'Intención',
      'category':    'Categoría',
      'start_date':  'Inicio',
      'end_date':    'Fin',
      'description': 'Descripción',
    },
    multiline: {'description'},
  ),
  'care_team': _SectionConfig(
    icon: Icons.groups,
    title: 'Equipo de cuidado',
    cardTitle: 'member_name',
    fields: {
      'member_name': null,
      'role':        'Rol',
      'member_type': 'Tipo',
      'name':        'Equipo',
      'status':      'Estado',
      'category':    'Categoría',
    },
  ),
};

// ── Pantalla ───────────────────────────────────────────────────────────────────
class PatientDetailScreen extends StatefulWidget {
  final String          patientId;
  final String          patientName;
  final LoginResponseDto currentUser;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.currentUser,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final PatientsService _service = PatientsService();
  PatientDetailModel? _patient;
  bool    _loading = true;
  String? _error;

  // Secciones expandidas — hospitalizacion y personal abiertas por defecto
  final Map<String, bool> _expanded = {
    'hospitalizacion': true,
    'personal':        false,
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
      // Inicializar estado colapsado para secciones dinámicas
      for (final key in p.sections.keys) {
        _expanded.putIfAbsent(key, () => false);
      }
      setState(() { _patient = p; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmt(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw.toString());
      final d = '${dt.day.toString().padLeft(2,'0')}/'
                '${dt.month.toString().padLeft(2,'0')}/'
                '${dt.year}';
      final s = raw.toString();
      if (s.contains('T') || s.contains(' ')) {
        return '$d  ${dt.hour.toString().padLeft(2,'0')}:'
               '${dt.minute.toString().padLeft(2,'0')}';
      }
      return d;
    } catch (_) { return raw.toString(); }
  }

  String _val(dynamic v) {
    if (v == null || v.toString().isEmpty) return '—';
    return v.toString();
  }

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

  String _initials(PatientDetailModel p) {
    final f = p.firstName.trim();
    final l = p.lastName.trim();
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    return f.isNotEmpty ? f[0].toUpperCase() : '?';
  }

  Color _severityColor(String s) => switch (s.toLowerCase()) {
    'severe' || 'high'       => Colors.red,
    'moderate' || 'medium'   => Colors.orange,
    'mild' || 'low'          => Colors.amber,
    _                        => Colors.grey,
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
      floatingActionButton: _patient == null ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => NotesScreen(
                  patientId:   widget.patientId,
                  patientName: _patient!.fullName,
                  currentUser: widget.currentUser,
                ),
              )),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.note_alt),
              label: const Text('Notas'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : _buildContent(_patient!, theme, isDark),
    );
  }

  Widget _buildContent(PatientDetailModel p, ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p, theme),
          const SizedBox(height: 20),

          // ── Hospitalización (fija) ────────────────────────────────────
          _CollapsibleSection(
            isDark: isDark,
            icon: Icons.local_hospital,
            title: 'Hospitalización',
            isExpanded: _expanded['hospitalizacion']!,
            onToggle: () => setState(() =>
                _expanded['hospitalizacion'] = !_expanded['hospitalizacion']!),
            child: Column(children: [
              _row(theme, 'Zona',          _val(p.ward)),
              _row(theme, 'Cama',          _val(p.bedNumber)),
              _row(theme, 'Ingreso',       _fmt(p.admissionDate)),
              _row(theme, 'Alta esperada', _fmt(p.expectedDischargeDate)),
              _rowMulti(theme, 'Diagnóstico principal',
                  _val(p.primaryDiagnosis)),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Datos personales (fija) ───────────────────────────────────
          _CollapsibleSection(
            isDark: isDark,
            icon: Icons.person,
            title: 'Datos personales',
            isExpanded: _expanded['personal']!,
            onToggle: () => setState(() =>
                _expanded['personal'] = !_expanded['personal']!),
            child: Column(children: [
              _row(theme, 'Nombre',       p.fullName),
              _row(theme, 'Nacimiento',   _fmt(p.birthDate)),
              _row(theme, 'Género',       _genderLabel(p.gender)),
              _row(theme, 'Estado civil', _maritalLabel(p.maritalStatus)),
              _row(theme, 'Teléfono',     _val(p.phone)),
              _row(theme, 'Idioma',       _val(p.language)),
              _row(theme, 'Etnia',        _val(p.ethnicity)),
              _rowMulti(theme, 'Dirección', _val(p.address)),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Secciones dinámicas ───────────────────────────────────────
          ...p.sections.entries.map((entry) {
            final key     = entry.key;
            final items   = entry.value;
            final config  = _sectionConfigs[key];
            final icon    = config?.icon  ?? Icons.list_alt;
            final title   = config?.title ?? key;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CollapsibleSection(
                isDark: isDark,
                icon: icon,
                title: title,
                badge: items.length,
                isExpanded: _expanded[key] ?? false,
                onToggle: () => setState(() =>
                    _expanded[key] = !(_expanded[key] ?? false)),
                child: items.isEmpty
                    ? _empty(theme, 'Sin registros')
                    : Column(
                        children: items.map((item) =>
                            _buildDynamicCard(item, config, theme, isDark)
                        ).toList(),
                      ),
              ),
            );
          }),

          // ── Información adicional (fija) ──────────────────────────────
          _CollapsibleSection(
            isDark: isDark,
            icon: Icons.info_outline,
            title: 'Información adicional',
            isExpanded: _expanded['adicional'] ?? false,
            onToggle: () => setState(() =>
                _expanded['adicional'] = !(_expanded['adicional'] ?? false)),
            child: Column(children: [
              _row(theme, 'Origen datos', _sourceLabel(p.sourceSystem)),
              _row(theme, 'Registrado',   _fmt(p.createdAt)),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Sub-tarjeta dinámica ───────────────────────────────────────────────────
  Widget _buildDynamicCard(
    Map<String, dynamic> item,
    _SectionConfig? config,
    ThemeData theme,
    bool isDark,
  ) {
    // Determinar título de la tarjeta
    String cardTitle = '—';
    if (config?.cardTitle != null) {
      cardTitle = _val(item[config!.cardTitle]);
    }

    // Color de severidad
    Color? severityColor;
    if (config?.severityField != null) {
      final sv = item[config!.severityField]?.toString() ?? '';
      if (sv.isNotEmpty) severityColor = _severityColor(sv);
    }

    // Filas a mostrar
    List<Widget> rows = [];

    if (config != null) {
      for (final entry in config.fields.entries) {
        final field = entry.key;
        final label = entry.value;
        if (label == null) continue;     // título ya usado arriba
        if (field == config.cardTitle) continue;

        final raw = item[field];
        if (raw == null || raw.toString().isEmpty) continue;

        // Caso especial: value + unit en observaciones
        if (field == 'value' && item.containsKey('unit')) {
          final v = _val(raw);
          final u = _val(item['unit']);
          final combined = u == '—' ? v : '$v $u';
          rows.add(config.multiline.contains(field)
              ? _rowMulti(theme, label, combined)
              : _row(theme, label, combined));
          continue;
        }
        if (field == 'unit') continue;   // ya combinado

        // Detectar si es fecha
        final display = _looksLikeDate(raw.toString())
            ? _fmt(raw) : _val(raw);

        rows.add(config.multiline.contains(field)
            ? _rowMulti(theme, label, display)
            : _row(theme, label, display));
      }
    } else {
      // Sin config: mostrar todos los campos que no sean id/external
      for (final entry in item.entries) {
        if (['id','external_id','source_system'].contains(entry.key)) continue;
        final raw = entry.value;
        if (raw == null || raw.toString().isEmpty) continue;
        final label = entry.key.replaceAll('_', ' ');
        final display = _looksLikeDate(raw.toString()) ? _fmt(raw) : _val(raw);
        rows.add(_row(theme, label, display));
      }
    }

    return Container(
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
            child: Row(children: [
              if (severityColor != null) ...[
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: severityColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(cardTitle,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          if (rows.isNotEmpty) ...[
            const Divider(height: 1),
            ...rows,
          ],
        ],
      ),
    );
  }

  bool _looksLikeDate(String s) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s);
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
            color: theme.textTheme.bodySmall?.color
                ?.withValues(alpha: 0.5))),
  );

  Widget _buildError(ThemeData theme) => Center(
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
  );
}

// ── Sección colapsable reutilizable ───────────────────────────────────────────
class _CollapsibleSection extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final int?         badge;
  final bool         isDark;
  final bool         isExpanded;
  final VoidCallback onToggle;
  final Widget       child;

  const _CollapsibleSection({
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
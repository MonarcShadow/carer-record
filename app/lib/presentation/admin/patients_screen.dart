import 'package:flutter/material.dart';
import '../../data/remote/patients_service.dart';
import '../../core/theme/theme.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final PatientsService _service = PatientsService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<PatientModel> _all      = [];
  List<PatientModel> _filtered = [];
  List<String>       _wards    = [];
  String  _selectedWard = 'todas';
  bool    _loading      = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _loadPatients();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() { _loading = true; _error = null; });
    try {
      final patients = await _service.getPatients();
      // ordenamiento — cambia givenName/familyName por firstName/lastName
      patients.sort((a, b) {
        final cmp = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        return cmp != 0 ? cmp : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });

      // Extraer zonas únicas para el filtro
      final wardSet = patients.map((p) => p.ward).toSet().toList()..sort();

      setState(() {
        _all    = patients;
        _wards  = wardSet;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = _all.where((p) {
        // Filtro por zona
        final zoneOk = _selectedWard == 'todas' || p.ward == _selectedWard;
        // Filtro por texto: busca en cualquier parte del nombre completo
        // _applyFilter — cambia givenName/familyName
        final nameOk = query.isEmpty ||
            p.fullName.toLowerCase().contains(query) ||
            p.lastName.toLowerCase().contains(query) ||
            p.firstName.toLowerCase().contains(query);
        return zoneOk && nameOk;
      }).toList();
    });
  }

  String _genderLabel(String g) {
    switch (g.toLowerCase()) {
      case 'male':   return 'Masculino';
      case 'female': return 'Femenino';
      default:       return g;
    }
  }

  // Inicial para el avatar
  // _initials
  String _initials(PatientModel p) {
    final f = p.firstName.trim();
    final l = p.lastName.trim();
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    if (f.isNotEmpty) return f[0].toUpperCase();
    return '?';
  }


  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pacientes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loadPatients,
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
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadPatients,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ── Buscador ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o apellido…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    // _applyFilter se dispara via listener
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),

                    // ── Chips de zona ─────────────────────────────────────
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        children: [
                          _WardChip(
                            label: 'Todas',
                            selected: _selectedWard == 'todas',
                            onTap: () {
                              setState(() => _selectedWard = 'todas');
                              _applyFilter();
                            },
                          ),
                          ..._wards.map((w) => _WardChip(
                            label: w,
                            selected: _selectedWard == w,
                            onTap: () {
                              setState(() => _selectedWard = w);
                              _applyFilter();
                            },
                          )),
                        ],
                      ),
                    ),

                    // ── Contador ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_filtered.length} paciente${_filtered.length != 1 ? 's' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),

                    // ── Lista ─────────────────────────────────────────────
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_search,
                                      size: 56,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Sin resultados',
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final p = _filtered[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.primary
                                          .withValues(alpha: 0.15),
                                      child: Text(
                                        _initials(p),
                                        style: const TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      p.fullName,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_genderLabel(p.gender)}  ·  Nac. ${p.birthDate}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        Text(
                                          'Cama ${p.bedNumber}  ·  Ingreso ${p.admissionDate}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        // Badge zona
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            p.ward,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    // Placeholder para cuando se implemente detalle
                                    trailing: Icon(
                                      Icons.chevron_right,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.5),
                                    ),
                                    onTap: () {
                                      // todo : navegar a detalle del paciente
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

// ── Widget auxiliar para chips de zona ────────────────────────────────────────
class _WardChip extends StatelessWidget {
  final String   label;
  final bool     selected;
  final VoidCallback onTap;

  const _WardChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        labelStyle: TextStyle(
          color: selected
              ? theme.colorScheme.onPrimary
              : theme.textTheme.bodyMedium?.color,
          fontWeight: FontWeight.w500,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
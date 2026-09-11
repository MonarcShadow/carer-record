import 'package:flutter/material.dart';
import '../../core/theme/cr_theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/remote/patients_service.dart';
import '../widgets/cr_widgets.dart';
import 'patient_detail_screen.dart';


class PatientsScreen extends StatefulWidget {
  final LoginResponseDto user;

  const PatientsScreen({super.key, required this.user});

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
      patients.sort((a, b) {
        final cmp = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        return cmp != 0 ? cmp : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });

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
        final zoneOk = _selectedWard == 'todas' || p.ward == _selectedWard;
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
  String _initials(PatientModel p) {
    final f = p.firstName.trim();
    final l = p.lastName.trim();
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    if (f.isNotEmpty) return f[0].toUpperCase();
    return '?';
  }


  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        elevation: 0,
        title: Text(
          'Pacientes',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: t.textPrimary),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: t.textSecondary),
            tooltip: 'Actualizar',
            onPressed: _loadPatients,
          ),
          const SizedBox(width: 4),
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
                          color: CR.red, size: 48),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(_error!,
                            style: const TextStyle(color: CR.red),
                            textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: CRPrimaryButton(
                          label: 'Reintentar',
                          height: 48,
                          onPressed: _loadPatients,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    CRSearchField(
                      controller: _searchCtrl,
                      hint: 'Buscar por nombre o apellido…',
                    ),

                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 20),
                        children: [
                          CRFilterChip(
                            label: 'Todas',
                            selected: _selectedWard == 'todas',
                            onTap: () {
                              setState(() => _selectedWard = 'todas');
                              _applyFilter();
                            },
                          ),
                          ..._wards.map((w) => CRFilterChip(
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

                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_filtered.length} paciente${_filtered.length != 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 12, color: t.textTertiary),
                        ),
                      ),
                    ),

                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_search,
                                      size: 52,
                                      color: t.textTertiary),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Sin resultados',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: t.textPrimary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final p = _filtered[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: t.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: t.cardShadow,
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                    leading: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: CR.mintSoft,
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _initials(p),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: t.isDark ? CR.mint : CR.mintInk,
                                          ),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      p.fullName,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_genderLabel(p.gender)}  ·  Nac. ${p.birthDate}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: t.textSecondary),
                                        ),
                                        Text(
                                          'Cama ${p.bedNumber}  ·  Ingreso ${p.admissionDate}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: t.textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: CR.mintSoft,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            p.ward,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: CR.mintInk,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: Icon(
                                      Icons.chevron_right,
                                      color: t.textTertiary,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PatientDetailScreen(
                                            patientId: p.id,
                                            patientName: p.fullName,
                                            currentUser: widget.user,
                                          ),
                                        ),
                                      );
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

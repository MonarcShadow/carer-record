import 'package:flutter/material.dart';
import '../../core/theme/cr_theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/remote/patients_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/cr_widgets.dart';
import '../admin/patient_detail_screen.dart';
import '../admin/users_screen.dart';
import '../admin/user_form_screen.dart';
import '../admin/patients_screen.dart';

class HomeScreen extends StatefulWidget {
  final LoginResponseDto user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PatientsService _service = PatientsService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<PatientModel> _all = [];
  List<PatientModel> _filtered = [];
  List<String> _wards = [];
  String _selectedWard = 'Todas';
  bool _loading = true;
  String? _error;

  static const _days = [
    'domingo', 'lunes', 'martes', 'miércoles',
    'jueves', 'viernes', 'sábado',
  ];
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await _service.getPatients();
      patients.sort((a, b) {
        final cmp =
            a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        return cmp != 0
            ? cmp
            : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });
      final wardSet = patients.map((p) => p.ward).where((w) => w.isNotEmpty).toSet().toList()
         ..sort();
      if (!mounted) return;
      setState(() {
        _all = patients;
        _wards = wardSet;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = _all.where((p) {
        final zoneOk = _selectedWard == 'Todas' || p.ward == _selectedWard;
        final nameOk =
            query.isEmpty ||
                p.fullName.toLowerCase().contains(query) ||
                p.lastName.toLowerCase().contains(query) ||
                p.firstName.toLowerCase().contains(query);
        return zoneOk && nameOk;
      }).toList();
    });
  }

  // ── Helpers de presentación ───────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'CR';
  }

  int? _ageOf(String birthDate) {
    final dt = DateTime.tryParse(birthDate);
    if (dt == null) return null;
    final now = DateTime.now();
    int age = now.year - dt.year;
    if (now.month < dt.month ||
        (now.month == dt.month && now.day < dt.day)) {
      age--;
    }
    return age;
  }

  String? _dayLabel(String admissionDate) {
    final dt = DateTime.tryParse(admissionDate);
    if (dt == null) return null;
    final now = DateTime.now();
    final a = DateTime(dt.year, dt.month, dt.day);
    final n = DateTime(now.year, now.month, now.day);
    final days = n.difference(a).inDays + 1;
    return days >= 1 ? 'Día $days' : null;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _dateLine() {
    final n = DateTime.now();
    final hh = n.hour.toString().padLeft(2, '0');
    final mm = n.minute.toString().padLeft(2, '0');
    return '${_days[n.weekday % 7]} ${n.day} de ${_months[n.month - 1]} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Scaffold(
      backgroundColor: t.background,
      drawer: AppDrawer(user: widget.user),
      body: SafeArea(
        child: Column(
          children: [
            // ── Cabecera ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(),
                            style:
                                TextStyle(fontSize: 15, color: t.textSecondary)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.user.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: t.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Turno activo + fecha
                  Column(
                    children: [
                      const CRShiftIndicator(),
                      const SizedBox(height: 6),
                      Text(
                        _dateLine(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: t.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: CRCircleAvatar(
                      initials: _initials(widget.user.userName),
                      size: 42,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // ── Título + búsqueda + filtro zona ──────────────────────────
            const CRLargeTitle(title: 'Casos activos'),
            CRSearchField(
              controller: _searchCtrl,
              hint: 'Buscar paciente por nombre…',
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 20),
                children: [
                  CRFilterChip(
                    label: 'Todas',
                    selected: _selectedWard == 'Todas',
                    onTap: () {
                      setState(() => _selectedWard = 'Todas');
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
            // ── Gestión (solo admin) ─────────────────────────────────────
            if (widget.user.userRole == 'admin') ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 4, 16, 0),
                child: CRSectionLabel(text: 'Gestión'),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _AdminTile(
                      icon: Icons.people,
                      label: 'Usuarios',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UsersScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _AdminTile(
                      icon: Icons.person_add,
                      label: 'Agregar médico',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const UserFormScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _AdminTile(
                      icon: Icons.local_hospital,
                      label: 'Pacientes',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PatientsScreen(user: widget.user)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // ── Lista de pacientes ───────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  color: CR.red, size: 44),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 40),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 14, color: CR.red),
                                ),
                              ),
                              const SizedBox(height: 16),
                              CRPrimaryButton(
                                label: 'Reintentar',
                                height: 48,
                                onPressed: _loadPatients,
                              ),
                            ],
                          ),
                        )
                      : _filtered.isEmpty
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
                                  const SizedBox(height: 4),
                                  Text('Ajusta la búsqueda o la zona',
                                      style:
                                          TextStyle(fontSize: 13, color: t.textTertiary)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 20),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final p = _filtered[i];
                                final age = _ageOf(p.birthDate);
                                return CRPatientCard(
                                  initials: _initials(p.fullName),
                                  name: p.fullName,
                                  meta:
                                      '${age ?? '—'} años · ${_genderLabel(p.gender)}',
                                  dayLabel: _dayLabel(p.admissionDate),
                                  locLine:
                                      '${p.bedNumber.isNotEmpty ? 'Cama ${p.bedNumber} · ' : ''}${p.ward}',
                                  diagnosis: p.primaryDiagnosis,
                                  statusLabel: 'Hospitalización activa',
                                  unitLabel:
                                      p.ward.isNotEmpty ? p.ward : null,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PatientDetailScreen(
                                        patientId: p.id,
                                        patientName: p.fullName,
                                        currentUser: widget.user,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  String _genderLabel(String g) {
    switch (g.toLowerCase()) {
      case 'male':
        return 'Hombre';
      case 'female':
        return 'Mujer';
      default:
        return '—';
    }
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: t.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.isDark ? t.chipBg : CR.mintSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    icon, size: 20, color: t.isDark ? CR.mint : CR.mintDark),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

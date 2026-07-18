import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';

// ── Modelo lista (liviano) ────────────────────────────────────────────────────
class PatientModel {
  final String id;
  final String firstName;
  final String lastName;
  final String birthDate;
  final String gender;
  final String ward;
  final String bedNumber;
  final String admissionDate;
  final String primaryDiagnosis;

  PatientModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.gender,
    required this.ward,
    required this.bedNumber,
    required this.admissionDate,
    required this.primaryDiagnosis,
  });

  String get fullName => '$firstName $lastName';

  factory PatientModel.fromJson(Map<String, dynamic> j) => PatientModel(
    id:               j['id']                as String? ?? '',
    firstName:        j['first_name']        as String? ?? '',
    lastName:         j['last_name']         as String? ?? '',
    birthDate:        j['birth_date']        as String? ?? '',
    gender:           j['gender']            as String? ?? '',
    ward:             j['ward']              as String? ?? 'Sin zona',
    bedNumber:        j['bed_number']        as String? ?? '',
    admissionDate:    j['admission_date']    as String? ?? '',
    primaryDiagnosis: j['primary_diagnosis'] as String? ?? '',
  );
}

// ── Modelo detalle (completo) ─────────────────────────────────────────────────
class PatientDetailModel {
  final String id;
  final String firstName;
  final String lastName;
  final String birthDate;
  final String gender;
  final String phone;
  final String address;
  final String maritalStatus;
  final String language;
  final String ethnicity;
  final String ward;
  final String bedNumber;
  final String admissionDate;
  final String expectedDischargeDate;
  final String primaryDiagnosis;
  final String sourceSystem;
  final String createdAt;

  PatientDetailModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.gender,
    required this.phone,
    required this.address,
    required this.maritalStatus,
    required this.language,
    required this.ethnicity,
    required this.ward,
    required this.bedNumber,
    required this.admissionDate,
    required this.expectedDischargeDate,
    required this.primaryDiagnosis,
    required this.sourceSystem,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  factory PatientDetailModel.fromJson(Map<String, dynamic> j) =>
      PatientDetailModel(
        id:                   j['id']                      as String? ?? '',
        firstName:            j['first_name']              as String? ?? '',
        lastName:             j['last_name']               as String? ?? '',
        birthDate:            j['birth_date']              as String? ?? '',
        gender:               j['gender']                  as String? ?? '',
        phone:                j['phone']                   as String? ?? '',
        address:              j['address']                 as String? ?? '',
        maritalStatus:        j['marital_status']          as String? ?? '',
        language:             j['language']                as String? ?? '',
        ethnicity:            j['ethnicity']               as String? ?? '',
        ward:                 j['ward']                    as String? ?? '',
        bedNumber:            j['bed_number']              as String? ?? '',
        admissionDate:        j['admission_date']          as String? ?? '',
        expectedDischargeDate: j['expected_discharge_date'] as String? ?? '',
        primaryDiagnosis:     j['primary_diagnosis']       as String? ?? '',
        sourceSystem:         j['source_system']           as String? ?? '',
        createdAt:            j['created_at']              as String? ?? '',
      );
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class PatientsService {
  final String _base = '${AppConfig.baseUrl}/api/v1/patients';

  Future<List<PatientModel>> getPatients() async {
    final res = await http.get(Uri.parse('$_base/'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(utf8.decode(res.bodyBytes));
      return data.map((e) => PatientModel.fromJson(e)).toList();
    }
    throw Exception('Error al cargar pacientes');
  }

  Future<PatientDetailModel> getPatientById(String id) async {
    final res = await http.get(Uri.parse('$_base/$id'));
    if (res.statusCode == 200) {
      return PatientDetailModel.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)),
      );
    }
    throw Exception('Error al cargar el paciente');
  }
}
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';

class PatientModel {
  final String id, firstName, lastName, birthDate, gender;
  final String ward, bedNumber, admissionDate, primaryDiagnosis;

  PatientModel({
    required this.id,       required this.firstName,
    required this.lastName, required this.birthDate,
    required this.gender,   required this.ward,
    required this.bedNumber, required this.admissionDate,
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

class PatientDetailModel {
  final String id, firstName, lastName, birthDate, gender;
  final String phone, address, maritalStatus, language, ethnicity;
  final String ward, bedNumber, admissionDate, expectedDischargeDate;
  final String primaryDiagnosis, sourceSystem, createdAt;
  // Secciones dinámicas: clave = nombre sección, valor = lista de registros
  final Map<String, List<Map<String, dynamic>>> sections;

  PatientDetailModel({
    required this.id,             required this.firstName,
    required this.lastName,       required this.birthDate,
    required this.gender,         required this.phone,
    required this.address,        required this.maritalStatus,
    required this.language,       required this.ethnicity,
    required this.ward,           required this.bedNumber,
    required this.admissionDate,  required this.expectedDischargeDate,
    required this.primaryDiagnosis, required this.sourceSystem,
    required this.createdAt,      required this.sections,
  });

  String get fullName => '$firstName $lastName';

  factory PatientDetailModel.fromJson(Map<String, dynamic> j) {
    final rawSections = j['sections'] as Map<String, dynamic>? ?? {};
    final sections = rawSections.map((key, value) => MapEntry(
      key,
      (value as List).map((e) => Map<String, dynamic>.from(e)).toList(),
    ));
    return PatientDetailModel(
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
      sections:             sections,
    );
  }
}

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
          jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Error al cargar el paciente');
  }
}
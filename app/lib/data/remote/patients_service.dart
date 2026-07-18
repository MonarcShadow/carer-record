import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';

class PatientModel {
  final String id;          // varchar(36)
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
}
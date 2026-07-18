import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';

// ── Lista ─────────────────────────────────────────────────────────────────────
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

// ── Sub-modelos ───────────────────────────────────────────────────────────────
class EncounterModel {
  final String type, status, startDate, endDate,
               reason, practitioner, referralReason, encounterClass;
  EncounterModel.fromJson(Map<String, dynamic> j)
      : type           = j['encounter_type']  as String? ?? '',
        status         = j['status']          as String? ?? '',
        startDate      = j['start_date']      as String? ?? '',
        endDate        = j['end_date']        as String? ?? '',
        reason         = j['reason']          as String? ?? '',
        practitioner   = j['practitioner_name'] as String? ?? '',
        referralReason = j['referral_reason'] as String? ?? '',
        encounterClass = j['encounter_class'] as String? ?? '';
}

class ConditionModel {
  final String description, status, severity,
               onsetDate, abatementDate, recordedBy;
  ConditionModel.fromJson(Map<String, dynamic> j)
      : description   = j['description']     as String? ?? '',
        status        = j['status']          as String? ?? '',
        severity      = j['severity']        as String? ?? '',
        onsetDate     = j['onset_date']      as String? ?? '',
        abatementDate = j['abatement_date']  as String? ?? '',
        recordedBy    = j['recorded_by']     as String? ?? '';
}

class MedicationModel {
  final String description, dosage, frequency, prescriber,
               instructions, status, startDate, endDate;
  MedicationModel.fromJson(Map<String, dynamic> j)
      : description  = j['description']  as String? ?? '',
        dosage       = j['dosage']       as String? ?? '',
        frequency    = j['frequency']    as String? ?? '',
        prescriber   = j['prescriber']   as String? ?? '',
        instructions = j['instructions'] as String? ?? '',
        status       = j['status']       as String? ?? '',
        startDate    = j['start_date']   as String? ?? '',
        endDate      = j['end_date']     as String? ?? '';
}

class ObservationModel {
  final String description, value, unit, valueHigh, valueLow,
               interpretation, category, status, effectiveDate;
  ObservationModel.fromJson(Map<String, dynamic> j)
      : description    = j['description']    as String? ?? '',
        value          = j['value']          as String? ?? '',
        unit           = j['unit']           as String? ?? '',
        valueHigh      = j['value_high']     as String? ?? '',
        valueLow       = j['value_low']      as String? ?? '',
        interpretation = j['interpretation'] as String? ?? '',
        category       = j['category']       as String? ?? '',
        status         = j['status']         as String? ?? '',
        effectiveDate  = j['effective_date'] as String? ?? '';
}

class AllergyModel {
  final String description, severity, status,
               onsetDate, reaction, lastOccurrence, recordedBy;
  AllergyModel.fromJson(Map<String, dynamic> j)
      : description    = j['description']     as String? ?? '',
        severity       = j['severity']        as String? ?? '',
        status         = j['status']          as String? ?? '',
        onsetDate      = j['onset_date']      as String? ?? '',
        reaction       = j['reaction']        as String? ?? '',
        lastOccurrence = j['last_occurrence'] as String? ?? '',
        recordedBy     = j['recorded_by']     as String? ?? '';
}

// ── Detalle completo ──────────────────────────────────────────────────────────
class PatientDetailModel {
  final String id, firstName, lastName, birthDate, gender;
  final String phone, address, maritalStatus, language, ethnicity;
  final String ward, bedNumber, admissionDate, expectedDischargeDate;
  final String primaryDiagnosis, sourceSystem, createdAt;
  final List<EncounterModel>   encounters;
  final List<ConditionModel>   conditions;
  final List<MedicationModel>  medications;
  final List<ObservationModel> observations;
  final List<AllergyModel>     allergies;

  PatientDetailModel.fromJson(Map<String, dynamic> j)
      : id                   = j['id']                       as String? ?? '',
        firstName             = j['first_name']               as String? ?? '',
        lastName              = j['last_name']                as String? ?? '',
        birthDate             = j['birth_date']               as String? ?? '',
        gender                = j['gender']                   as String? ?? '',
        phone                 = j['phone']                    as String? ?? '',
        address               = j['address']                  as String? ?? '',
        maritalStatus         = j['marital_status']           as String? ?? '',
        language              = j['language']                 as String? ?? '',
        ethnicity             = j['ethnicity']                as String? ?? '',
        ward                  = j['ward']                     as String? ?? '',
        bedNumber             = j['bed_number']               as String? ?? '',
        admissionDate         = j['admission_date']           as String? ?? '',
        expectedDischargeDate = j['expected_discharge_date']  as String? ?? '',
        primaryDiagnosis      = j['primary_diagnosis']        as String? ?? '',
        sourceSystem          = j['source_system']            as String? ?? '',
        createdAt             = j['created_at']               as String? ?? '',
        encounters   = (j['encounters']   as List? ?? [])
            .map((e) => EncounterModel.fromJson(e)).toList(),
        conditions   = (j['conditions']   as List? ?? [])
            .map((e) => ConditionModel.fromJson(e)).toList(),
        medications  = (j['medications']  as List? ?? [])
            .map((e) => MedicationModel.fromJson(e)).toList(),
        observations = (j['observations'] as List? ?? [])
            .map((e) => ObservationModel.fromJson(e)).toList(),
        allergies    = (j['allergies']    as List? ?? [])
            .map((e) => AllergyModel.fromJson(e)).toList();

  String get fullName => '$firstName $lastName';
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
          jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Error al cargar el paciente');
  }
}
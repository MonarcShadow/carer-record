"""
Adaptador FHIR R4 Completo
==========================
Lee bundles JSON generados por Synthea o descargados desde HAPI FHIR
e importa todos los recursos clínicos a la base de datos de Carer Record.

Uso:
    python fhir_adapter.py --input ./fhir/

Requisitos:
    pip install mysql-connector-python
"""

import json
import uuid
import argparse
import logging
from pathlib import Path
from datetime import datetime

import mysql.connector

# ── Configuración ─────────────────────────────────────────────────────────────

DB_CONFIG = {
    "host":     "localhost",
    "user":     "admin",
    "password": "admin",
    "database": "carer_record",
}

# URLs de extensiones FHIR de ubicación hospitalaria
# Deben coincidir con las que agrega enrich_patients.py en el PC
EXTENSION_URLS = {
    "ward":           "urn:hospital-simulado:fhir:ward",
    "bed_number":     "urn:hospital-simulado:fhir:bed-number",
    "admission_date": "urn:hospital-simulado:fhir:admission-date",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

# ── Helpers de mapeo FHIR ─────────────────────────────────────────────────────

def _gender(fhir_gender: str) -> str:
    return {"male": "male", "female": "female"}.get(fhir_gender or "", "unknown")


def _date(fhir_date: str):
    if not fhir_date:
        return None
    try:
        return datetime.strptime(fhir_date[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def _datetime(fhir_dt: str):
    if not fhir_dt:
        return None
    try:
        return datetime.strptime(fhir_dt[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def _name(fhir_names: list) -> tuple:
    for n in fhir_names:
        given  = " ".join(n.get("given", []))
        family = n.get("family", "")
        if given or family:
            return given, family
    return "", ""


def _identifier(identifiers: list) -> str:
    return identifiers[0].get("value") if identifiers else None


def _code_display(codeable_concept: dict) -> str:
    if not codeable_concept:
        return ""
    if "text" in codeable_concept:
        return codeable_concept["text"]
    for coding in codeable_concept.get("coding", []):
        if "display" in coding:
            return coding["display"]
    return ""


def _code_value(codeable_concept: dict) -> str:
    if not codeable_concept:
        return ""
    for coding in codeable_concept.get("coding", []):
        if "code" in coding:
            return coding["code"]
    return ""


def _code_system(codeable_concept: dict) -> str:
    if not codeable_concept:
        return ""
    for coding in codeable_concept.get("coding", []):
        if "system" in coding:
            return coding["system"]
    return ""


def _extract_ref_id(reference_str: str) -> str:
    if not reference_str:
        return ""
    return reference_str.split(":")[-1].split("/")[-1]


def _patient_ref(resource: dict) -> str:
    ref = resource.get("subject", resource.get("patient", {}))
    return _extract_ref_id(ref.get("reference", ""))


def _truncate(value, length: int) -> str:
    if not value:
        return ""
    return str(value)[:length]


# ── Extracción de datos demográficos extendidos ───────────────────────────────

def _extract_patient_extended(res: dict) -> dict:
    phone = ""
    for telecom in res.get("telecom", []):
        if telecom.get("system") == "phone":
            phone = telecom.get("value", "")
            break

    address = ""
    addresses = res.get("address", [])
    if addresses:
        addr  = addresses[0]
        parts = addr.get("line", []) + [
            addr.get("city", ""),
            addr.get("state", ""),
            addr.get("country", ""),
        ]
        address = ", ".join(p for p in parts if p)

    marital = _code_display(res.get("maritalStatus"))

    language = ""
    communications = res.get("communication", [])
    if communications:
        lang     = communications[0].get("language", {})
        language = _code_display(lang) or _code_value(lang)

    ethnicity = ""
    for ext in res.get("extension", []):
        url = ext.get("url", "")
        if "ethnicity" in url or "race" in url:
            for sub_ext in ext.get("extension", []):
                if sub_ext.get("url") == "text":
                    ethnicity = sub_ext.get("valueString", "")
                    break
            if ethnicity:
                break

    deceased      = bool(res.get("deceasedBoolean") or res.get("deceasedDateTime"))
    deceased_date = _date(res.get("deceasedDateTime"))

    return {
        "phone":          _truncate(phone, 50),
        "address":        _truncate(address, 300),
        "marital_status": _truncate(marital, 50),
        "language":       _truncate(language, 50),
        "ethnicity":      _truncate(ethnicity, 100),
        "deceased":       deceased,
        "deceased_date":  deceased_date,
    }


def _extract_location(entries: list, patient_ext_id: str) -> dict:
    """
    Lee ward, bed_number y admission_date desde las extensiones del recurso Patient
    agregadas por enrich_patients.py. Fallback al Encounter más reciente.
    """
    # Prioridad: extensiones del Patient
    for entry in entries:
        res = entry.get("resource", {})
        if res.get("resourceType") != "Patient":
            continue
        if res.get("id") != patient_ext_id:
            continue

        ward = bed_number = admission_date = None

        for ext in res.get("extension", []):
            url = ext.get("url", "")
            if url == EXTENSION_URLS["ward"]:
                ward = ext.get("valueString")
            elif url == EXTENSION_URLS["bed_number"]:
                bed_number = ext.get("valueString")
            elif url == EXTENSION_URLS["admission_date"]:
                admission_date = _datetime(ext.get("valueDateTime"))

        if ward:
            return {
                "ward":           ward,
                "bed_number":     _truncate(bed_number, 20) if bed_number else None,
                "admission_date": admission_date,
            }

    # Fallback: Encounter más reciente
    latest_encounter = None
    latest_date      = None

    for entry in entries:
        res = entry.get("resource", {})
        if res.get("resourceType") != "Encounter":
            continue
        pat_ref = _extract_ref_id(res.get("subject", {}).get("reference", ""))
        if pat_ref != patient_ext_id:
            continue
        locations = res.get("location", [])
        if not locations:
            continue
        period    = res.get("period", {})
        start_str = period.get("start", "")
        if start_str and (latest_date is None or start_str > latest_date):
            latest_date      = start_str
            latest_encounter = res

    if not latest_encounter:
        return {"ward": None, "bed_number": None, "admission_date": None}

    display    = latest_encounter["location"][0].get("location", {}).get("display", "")
    period     = latest_encounter.get("period", {})
    ward       = None
    bed_number = None

    if " - Cama " in display:
        parts      = display.split(" - Cama ")
        ward       = parts[0].replace("Sala ", "").strip()
        bed_number = parts[1].strip() if len(parts) > 1 else None
    elif display:
        ward = _truncate(display, 100)

    return {
        "ward":           ward,
        "bed_number":     _truncate(bed_number, 20) if bed_number else None,
        "admission_date": _datetime(period.get("start")),
    }


# ── Importación ───────────────────────────────────────────────────────────────

def import_bundle(conn, bundle_path: Path) -> dict:
    stats = {
        "patients":          0,
        "encounters":        0,
        "conditions":        0,
        "medications":       0,
        "observations":      0,
        "allergies":         0,
        "procedures":        0,
        "immunizations":     0,
        "diagnostic_reports":0,
        "imaging_studies":   0,
        "care_plans":        0,
        "care_teams":        0,
        "devices":           0,
        "skipped":           0,
        "errors":            0,
    }
    cursor = conn.cursor()

    with open(bundle_path, encoding="utf-8") as f:
        bundle = json.load(f)

    entries     = bundle.get("entry", [])
    patient_map = {}

    # ── PASO 1: Pacientes ──────────────────────────────────────────────────────
    for entry in entries:
        res = entry.get("resource", {})
        if res.get("resourceType") != "Patient":
            continue

        ext_id = res.get("id")

        cursor.execute(
            "SELECT id FROM fhir_sync_log WHERE resource_type='Patient' AND resource_id=%s",
            (ext_id,),
        )
        existing_log = cursor.fetchone()

        cursor.execute(
            "SELECT id FROM patients WHERE external_id=%s",
            (ext_id,),
        )
        existing_patient = cursor.fetchone()

        if existing_patient:
            patient_map[ext_id] = existing_patient[0]
            if existing_log:
                stats["skipped"] += 1
            continue

        internal_id = str(uuid.uuid4())
        first, last = _name(res.get("name", []))
        extended    = _extract_patient_extended(res)
        location    = _extract_location(entries, ext_id)

        try:
            cursor.execute(
                """
                INSERT INTO patients
                    (id, external_id, source_system,
                     first_name, last_name, birth_date, gender, local_id,
                     phone, address, marital_status, language, ethnicity,
                     deceased, deceased_date,
                     ward, bed_number, admission_date)
                VALUES (%s, %s, 'fhir', %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s)
                """,
                (
                    internal_id, ext_id,
                    first, last,
                    _date(res.get("birthDate")),
                    _gender(res.get("gender")),
                    _identifier(res.get("identifier", [])),
                    extended["phone"],
                    extended["address"],
                    extended["marital_status"],
                    extended["language"],
                    extended["ethnicity"],
                    extended["deceased"],
                    extended["deceased_date"],
                    location["ward"],
                    location["bed_number"],
                    location["admission_date"],
                ),
            )
            cursor.execute(
                """
                INSERT IGNORE INTO fhir_sync_log
                    (id, resource_type, resource_id, bundle_file, status)
                VALUES (%s, 'Patient', %s, %s, 'success')
                """,
                (str(uuid.uuid4()), ext_id, bundle_path.name),
            )
            patient_map[ext_id] = internal_id
            stats["patients"] += 1

        except Exception as exc:
            log.error("Error paciente %s: %s", ext_id, exc)
            stats["errors"] += 1

    # ── PASO 2: Recursos clínicos ──────────────────────────────────────────────
    CLINICAL_TYPES = {
        "Encounter", "Condition", "MedicationRequest",
        "Observation", "AllergyIntolerance", "Procedure",
        "Immunization", "DiagnosticReport", "ImagingStudy",
        "CarePlan", "CareTeam", "Device",
    }

    for entry in entries:
        res    = entry.get("resource", {})
        rtype  = res.get("resourceType")
        res_id = res.get("id", str(uuid.uuid4()))

        if rtype not in CLINICAL_TYPES:
            continue

        pat_ext_id      = _patient_ref(res)
        internal_pat_id = patient_map.get(pat_ext_id)

        if not internal_pat_id:
            continue

        cursor.execute(
            "SELECT id FROM fhir_sync_log WHERE resource_type=%s AND resource_id=%s",
            (rtype, res_id),
        )
        if cursor.fetchone():
            stats["skipped"] += 1
            continue

        try:
            if rtype == "Encounter":
                period         = res.get("period", {})
                types          = res.get("type", [])
                encounter_type = _code_display(types[0]) if types else ""
                enc_class      = res.get("class", {})
                class_code     = enc_class.get("code", "") if isinstance(enc_class, dict) else ""

                practitioner = ""
                for participant in res.get("participant", []):
                    individual = participant.get("individual", {})
                    display    = individual.get("display", "")
                    ptype      = participant.get("type", [])
                    is_primary = any(
                        _code_value(t) in ("PART", "PPRF", "ATND")
                        for t in ptype
                    )
                    if display and (is_primary or not practitioner):
                        practitioner = display

                cursor.execute(
                    """
                    INSERT INTO encounters
                        (id, patient_id, external_id, source_system,
                         encounter_type, status, start_date, end_date,
                         reason, practitioner_name, encounter_class)
                    VALUES (%s, %s, %s, 'fhir', %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(encounter_type, 100),
                        _truncate(res.get("status"), 50),
                        _datetime(period.get("start")),
                        _datetime(period.get("end")),
                        _code_display(res.get("reasonCode", [{}])[0])
                        if res.get("reasonCode") else "",
                        _truncate(practitioner, 200),
                        _truncate(class_code, 50),
                    ),
                )
                stats["encounters"] += 1

            elif rtype == "Condition":
                clinical = res.get("clinicalStatus", {})
                severity = res.get("severity", {})
                asserter = res.get("asserter", {})

                cursor.execute(
                    """
                    INSERT INTO conditions
                        (id, patient_id, external_id,
                         code, code_system, description,
                         status, severity, recorded_by,
                         onset_date, abatement_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("code")), 50),
                        _truncate(_code_system(res.get("code")), 100),
                        _code_display(res.get("code")),
                        _truncate(_code_display(clinical) or "active", 50),
                        _truncate(_code_display(severity), 50),
                        _truncate(asserter.get("display", ""), 200),
                        _date(res.get("onsetDateTime") or res.get("recordedDate")),
                        _date(res.get("abatementDateTime") or res.get("abatementDate")),
                    ),
                )
                stats["conditions"] += 1

            elif rtype == "MedicationRequest":
                med_concept = res.get("medicationCodeableConcept", {})
                dosage_list = res.get("dosageInstruction", [])
                dosage      = dosage_list[0] if dosage_list else {}
                requester   = res.get("requester", {})
                dose_text   = dosage.get("text", "")
                timing      = dosage.get("timing", {}).get("code", {})
                freq_text   = _code_display(timing) or str(
                    dosage.get("timing", {}).get("repeat", {}).get("periodUnit", "")
                )

                cursor.execute(
                    """
                    INSERT INTO medications
                        (id, patient_id, external_id,
                         code, code_system, description,
                         dosage, frequency, prescriber, instructions,
                         status, start_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(med_concept), 50),
                        _truncate(_code_system(med_concept), 100),
                        _code_display(med_concept),
                        _truncate(dose_text, 200),
                        _truncate(freq_text, 100),
                        _truncate(requester.get("display", ""), 200),
                        dosage.get("patientInstruction", ""),
                        _truncate(res.get("status", "active"), 50),
                        _date(res.get("authoredOn")),
                    ),
                )
                stats["medications"] += 1

            elif rtype == "Observation":
                value_qty   = res.get("valueQuantity", {})
                value_str   = _truncate(str(value_qty.get("value", "")), 500) if value_qty else ""
                value_str   = value_str or _truncate(res.get("valueString", ""), 500)
                categories  = res.get("category", [])
                category    = _code_display(categories[0]) if categories else ""
                interp_list = res.get("interpretation", [])
                interp      = _code_display(interp_list[0]) if interp_list else ""

                value_high = ""
                value_low  = ""
                for comp in res.get("component", []):
                    comp_code  = _code_display(comp.get("code", {})).lower()
                    comp_val   = comp.get("valueQuantity", {})
                    comp_value = str(comp_val.get("value", ""))
                    if "systolic" in comp_code:
                        value_high = _truncate(comp_value, 100)
                    elif "diastolic" in comp_code:
                        value_low = _truncate(comp_value, 100)

                cursor.execute(
                    """
                    INSERT INTO observations
                        (id, patient_id, external_id,
                         code, code_system, description,
                         value, value_high, value_low,
                         unit, interpretation, category,
                         status, effective_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("code")), 50),
                        _truncate(_code_system(res.get("code")), 100),
                        _truncate(_code_display(res.get("code")) or category, 500),
                        value_str,
                        value_high,
                        value_low,
                        _truncate(value_qty.get("unit", ""), 50),
                        _truncate(interp, 50),
                        _truncate(category, 100),
                        _truncate(res.get("status"), 50),
                        _datetime(res.get("effectiveDateTime")),
                    ),
                )
                stats["observations"] += 1

            elif rtype == "AllergyIntolerance":
                clinical      = res.get("clinicalStatus", {})
                reactions     = res.get("reaction", [])
                reaction_text = ""
                if reactions:
                    manifestations = reactions[0].get("manifestation", [])
                    reaction_text  = "; ".join(
                        _code_display(m) for m in manifestations if _code_display(m)
                    )
                last_occ = res.get("lastOccurrence")
                recorder = res.get("recorder", {})

                cursor.execute(
                    """
                    INSERT INTO allergies
                        (id, patient_id, external_id,
                         code, code_system, description,
                         severity, status, onset_date,
                         reaction, last_occurrence, recorded_by)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("code")), 50),
                        _truncate(_code_system(res.get("code")), 100),
                        _code_display(res.get("code")),
                        _truncate(res.get("criticality", ""), 50),
                        _truncate(_code_display(clinical) or "active", 50),
                        _date(res.get("onsetDateTime")),
                        reaction_text,
                        _date(last_occ),
                        _truncate(recorder.get("display", ""), 200),
                    ),
                )
                stats["allergies"] += 1

            elif rtype == "Procedure":
                performed = res.get("performedDateTime") or res.get("performedPeriod", {}).get("start")
                performers = res.get("performer", [])
                performer  = performers[0].get("actor", {}).get("display", "") if performers else ""
                body_sites = res.get("bodySite", [])
                body_site  = _code_display(body_sites[0]) if body_sites else ""
                reasons    = res.get("reasonCode", [])
                reason     = _code_display(reasons[0]) if reasons else ""

                cursor.execute(
                    """
                    INSERT INTO procedures
                        (id, patient_id, external_id,
                         code, code_system, description,
                         status, performed_date, performer,
                         reason, body_site)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("code")), 50),
                        _truncate(_code_system(res.get("code")), 100),
                        _code_display(res.get("code")),
                        _truncate(res.get("status", ""), 50),
                        _datetime(performed),
                        _truncate(performer, 200),
                        _truncate(reason, 500),
                        _truncate(body_site, 200),
                    ),
                )
                stats["procedures"] += 1

            elif rtype == "Immunization":
                performers = res.get("performer", [])
                performer  = performers[0].get("actor", {}).get("display", "") if performers else ""
                site       = _code_display(res.get("site", {}))
                route      = _code_display(res.get("route", {}))

                cursor.execute(
                    """
                    INSERT INTO immunizations
                        (id, patient_id, external_id,
                         code, code_system, description,
                         status, occurrence_date, lot_number,
                         manufacturer, site, route, performer)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("vaccineCode", {})), 50),
                        _truncate(_code_system(res.get("vaccineCode", {})), 100),
                        _code_display(res.get("vaccineCode", {})),
                        _truncate(res.get("status", ""), 50),
                        _datetime(res.get("occurrenceDateTime")),
                        _truncate(res.get("lotNumber", ""), 100),
                        _truncate(res.get("manufacturer", {}).get("display", ""), 200),
                        _truncate(site, 100),
                        _truncate(route, 100),
                        _truncate(performer, 200),
                    ),
                )
                stats["immunizations"] += 1

            elif rtype == "DiagnosticReport":
                categories  = res.get("category", [])
                category    = _code_display(categories[0]) if categories else ""
                performers  = res.get("performer", [])
                performer   = performers[0].get("display", "") if performers else ""
                conclusions = res.get("conclusionCode", [])
                conclusion  = _code_display(conclusions[0]) if conclusions else res.get("conclusion", "")

                cursor.execute(
                    """
                    INSERT INTO diagnostic_reports
                        (id, patient_id, external_id,
                         code, code_system, description,
                         category, status, effective_date,
                         issued_date, performer, conclusion)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("code")), 50),
                        _truncate(_code_system(res.get("code")), 100),
                        _code_display(res.get("code")),
                        _truncate(category, 100),
                        _truncate(res.get("status", ""), 50),
                        _datetime(res.get("effectiveDateTime")),
                        _datetime(res.get("issued")),
                        _truncate(performer, 200),
                        _truncate(conclusion, 500) if conclusion else "",
                    ),
                )
                stats["diagnostic_reports"] += 1

            elif rtype == "ImagingStudy":
                series     = res.get("series", [])
                modalities = set()
                instances  = 0
                body_site  = ""
                for s in series:
                    mod = s.get("modality", {})
                    if mod.get("code"):
                        modalities.add(mod["code"])
                    instances += len(s.get("instance", []))
                    if not body_site:
                        body_site = _code_display(s.get("bodySite", {}))

                referrer = res.get("referrer", {}).get("display", "")

                cursor.execute(
                    """
                    INSERT INTO imaging_studies
                        (id, patient_id, external_id,
                         modality, description, status,
                         started_date, number_series, number_instances,
                         body_site, referrer)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(", ".join(modalities), 50),
                        _truncate(res.get("description", ""), 500),
                        _truncate(res.get("status", ""), 50),
                        _datetime(res.get("started")),
                        len(series),
                        instances,
                        _truncate(body_site, 200),
                        _truncate(referrer, 200),
                    ),
                )
                stats["imaging_studies"] += 1

            elif rtype == "CarePlan":
                categories = res.get("category", [])
                category   = _code_display(categories[0]) if categories else ""
                period     = res.get("period", {})

                cursor.execute(
                    """
                    INSERT INTO care_plans
                        (id, patient_id, external_id,
                         title, description, status,
                         intent, category, start_date, end_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(res.get("title", ""), 300),
                        res.get("description", ""),
                        _truncate(res.get("status", ""), 50),
                        _truncate(res.get("intent", ""), 50),
                        _truncate(category, 200),
                        _datetime(period.get("start")),
                        _datetime(period.get("end")),
                    ),
                )
                stats["care_plans"] += 1

            elif rtype == "CareTeam":
                categories  = res.get("category", [])
                category    = _code_display(categories[0]) if categories else ""
                period      = res.get("period", {})
                care_team_id = str(uuid.uuid4())

                cursor.execute(
                    """
                    INSERT INTO care_teams
                        (id, patient_id, external_id,
                         name, status, category,
                         start_date, end_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        care_team_id, internal_pat_id, res_id,
                        _truncate(res.get("name", ""), 300),
                        _truncate(res.get("status", ""), 50),
                        _truncate(category, 200),
                        _datetime(period.get("start")),
                        _datetime(period.get("end")),
                    ),
                )

                for participant in res.get("participant", []):
                    roles   = participant.get("role", [])
                    role    = _code_display(roles[0]) if roles else ""
                    member  = participant.get("member", {})
                    m_name  = member.get("display", "")
                    m_type  = member.get("reference", "").split("/")[0] if member.get("reference") else ""

                    cursor.execute(
                        """
                        INSERT INTO care_team_members
                            (id, care_team_id, patient_id,
                             role, member_name, member_type)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        """,
                        (
                            str(uuid.uuid4()), care_team_id, internal_pat_id,
                            _truncate(role, 200),
                            _truncate(m_name, 200),
                            _truncate(m_type, 100),
                        ),
                    )
                stats["care_teams"] += 1

            elif rtype == "Device":
                udi_carriers = res.get("udiCarrier", [])
                udi          = udi_carriers[0].get("deviceIdentifier", "") if udi_carriers else ""
                device_name  = res.get("deviceName", [])
                description  = device_name[0].get("name", "") if device_name else _code_display(res.get("type", {}))

                cursor.execute(
                    """
                    INSERT INTO devices
                        (id, patient_id, external_id,
                         code, code_system, description,
                         status, manufacturer, model,
                         lot_number, serial_number,
                         expiration_date, udi)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()), internal_pat_id, res_id,
                        _truncate(_code_value(res.get("type", {})), 50),
                        _truncate(_code_system(res.get("type", {})), 100),
                        _truncate(description, 500),
                        _truncate(res.get("status", ""), 50),
                        _truncate(res.get("manufacturer", ""), 200),
                        _truncate(res.get("modelNumber", ""), 200),
                        _truncate(res.get("lotNumber", ""), 100),
                        _truncate(res.get("serialNumber", ""), 100),
                        _date(res.get("expirationDate")),
                        _truncate(udi, 300),
                    ),
                )
                stats["devices"] += 1

            cursor.execute(
                """
                INSERT IGNORE INTO fhir_sync_log
                    (id, resource_type, resource_id, bundle_file, status)
                VALUES (%s, %s, %s, %s, 'success')
                """,
                (str(uuid.uuid4()), rtype, res_id, bundle_path.name),
            )

        except Exception as exc:
            log.debug("Error %s %s: %s", rtype, res_id, exc)
            stats["errors"] += 1

    conn.commit()
    cursor.close()
    return stats


# ── Entry point ───────────────────────────────────────────────────────────────

def run(input_dir: str):
    fhir_path = Path(input_dir)
    bundles   = list(fhir_path.glob("*.json"))

    if not bundles:
        log.warning("No se encontraron JSON en %s", fhir_path)
        return

    log.info("Conectando a MariaDB...")
    conn  = mysql.connector.connect(**DB_CONFIG)
    total = {k: 0 for k in (
        "patients", "encounters", "conditions", "medications",
        "observations", "allergies", "procedures", "immunizations",
        "diagnostic_reports", "imaging_studies", "care_plans",
        "care_teams", "devices", "skipped", "errors"
    )}

    for bundle_path in sorted(bundles):
        log.info("Procesando: %s", bundle_path.name)
        stats = import_bundle(conn, bundle_path)
        for k in total:
            total[k] += stats[k]

    conn.close()

    log.info("\n=== Importación completa ===")
    for k, v in total.items():
        log.info("  %-20s: %d", k.capitalize(), v)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Importador FHIR R4 → MariaDB")
    parser.add_argument(
        "--input", required=True,
        help="Directorio con bundles JSON de Synthea",
    )
    args = parser.parse_args()
    run(args.input)
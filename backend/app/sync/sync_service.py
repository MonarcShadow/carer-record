#!/usr/bin/env python3
"""
Servicio de sincronización FHIR R4 → MariaDB (multi-clínica)
==============================================================
Consulta un servidor FHIR periódicamente usando _lastUpdated para traer
solo los recursos modificados desde la última sincronización.

La configuración específica de cada clínica (tipos de recursos a
sincronizar, nombres de tabla, extensiones FHIR propietarias, y
capacidades del servidor) vive en un JSON externo, apuntado por
CLINIC_CONFIG en el .env. Esto permite reusar este mismo script
contra distintos sistemas de distintas clínicas sin tocar código.

Ejecutar como servicio systemd:
    python3 -m app.sync.sync_service
"""
import re
import time
import json
import uuid
import logging
import requests
from pathlib import Path
from datetime import datetime, timezone
from dotenv import load_dotenv
import os
import mysql.connector

# ── Config ────────────────────────────────────────────────────────────────────
load_dotenv(Path(__file__).parent.parent.parent / '.env')
STATE_FILE          = Path(__file__).parent.parent.parent / 'fhir_sync_state.json'
CLINIC_CONFIG_PATH  = Path(os.getenv(
    'CLINIC_CONFIG',
    str(Path(__file__).parent.parent.parent / 'config' / 'clinics' / 'carer-record.json')
))

DB_CONFIG = {
    "host":     "localhost",
    "user":     os.getenv('DB_USER', 'admin'),
    "password": os.getenv('DB_PASSWORD', 'admin'),
    "database": os.getenv('DB_NAME', 'carer_record'),
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [sync_service] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Configuración de la clínica ────────────────────────────────────────────────

# Nombres de tabla por defecto, usados como fallback si el JSON de la
# clínica no define alguno (o no define "tables" en absoluto).
DEFAULT_TABLES = {
    "Patient":            "patients",
    "Encounter":          "encounters",
    "Condition":          "conditions",
    "MedicationRequest":  "medications",
    "Observation":        "observations",
    "AllergyIntolerance": "allergies",
    "Procedure":          "procedures",
    "Immunization":       "immunizations",
    "DiagnosticReport":   "diagnostic_reports",
    "ImagingStudy":       "imaging_studies",
    "CarePlan":           "care_plans",
    "CareTeam":           "care_teams",
    "Device":             "devices",
    "CareTeamMembers":    "care_team_members",
    "SyncLog":            "fhir_sync_log",
}

_IDENTIFIER_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def _safe_identifier(name: str, fallback: str) -> str:
    """
    Valida que un nombre de tabla venga limpio (solo letras/números/_).
    El JSON de config es un archivo local de confianza, pero igual se
    valida antes de interpolarlo en SQL para evitar errores por config
    mal escrita (nunca se usa input directo del usuario final aquí).
    """
    if name and _IDENTIFIER_RE.match(name):
        return name
    log.warning("Nombre de tabla inválido '%s', usando '%s'", name, fallback)
    return fallback


def load_clinic_config() -> dict:
    if not CLINIC_CONFIG_PATH.exists():
        log.warning(
            "No se encontró config de clínica en %s, usando valores por defecto",
            CLINIC_CONFIG_PATH,
        )
        return {}
    try:
        return json.loads(CLINIC_CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception as e:
        log.error("Error leyendo %s: %s — usando valores por defecto", CLINIC_CONFIG_PATH, e)
        return {}


CLINIC = load_clinic_config()

RESOURCE_TYPES = CLINIC.get("resource_types") or list(DEFAULT_TABLES.keys() - {"CareTeamMembers", "SyncLog"})

EXTENSION_URLS = CLINIC.get("extension_urls", {
    "ward":           "urn:hospital-simulado:fhir:ward",
    "bed_number":     "urn:hospital-simulado:fhir:bed-number",
    "admission_date": "urn:hospital-simulado:fhir:admission-date",
})

CAPABILITIES = CLINIC.get("capabilities", {
    "supports_chained_search": False,
    "supports_deceased_filter": False,
})

_raw_tables = CLINIC.get("tables", {})
TABLES = {
    key: _safe_identifier(_raw_tables.get(key, default), default)
    for key, default in DEFAULT_TABLES.items()
}

# Atajos usados en los upserts de más abajo
TBL_PATIENTS      = TABLES["Patient"]
TBL_ENCOUNTERS    = TABLES["Encounter"]
TBL_CONDITIONS    = TABLES["Condition"]
TBL_MEDICATIONS   = TABLES["MedicationRequest"]
TBL_OBSERVATIONS  = TABLES["Observation"]
TBL_ALLERGIES     = TABLES["AllergyIntolerance"]
TBL_PROCEDURES    = TABLES["Procedure"]
TBL_IMMUNIZATIONS = TABLES["Immunization"]
TBL_DIAG_REPORTS  = TABLES["DiagnosticReport"]
TBL_IMAGING       = TABLES["ImagingStudy"]
TBL_CARE_PLANS    = TABLES["CarePlan"]
TBL_CARE_TEAMS    = TABLES["CareTeam"]
TBL_CT_MEMBERS    = TABLES["CareTeamMembers"]
TBL_DEVICES       = TABLES["Device"]
TBL_SYNC_LOG      = TABLES["SyncLog"]

# resourceType FHIR → columna de tabla usada en cada upsert
_TABLE_BY_RTYPE = {
    "Encounter":          TBL_ENCOUNTERS,
    "Condition":          TBL_CONDITIONS,
    "MedicationRequest":  TBL_MEDICATIONS,
    "Observation":        TBL_OBSERVATIONS,
    "AllergyIntolerance": TBL_ALLERGIES,
    "Procedure":          TBL_PROCEDURES,
    "Immunization":       TBL_IMMUNIZATIONS,
    "DiagnosticReport":   TBL_DIAG_REPORTS,
    "ImagingStudy":       TBL_IMAGING,
    "CarePlan":           TBL_CARE_PLANS,
    "CareTeam":           TBL_CARE_TEAMS,
    "Device":             TBL_DEVICES,
}

# ── Estado de sincronización ──────────────────────────────────────────────────

def load_state() -> dict:
    """Lee el timestamp de última sincronización por tipo de recurso."""
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            pass
    return {}

def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, indent=2))

# ── Cliente FHIR ──────────────────────────────────────────────────────────────

def fetch_page(url: str, params: dict | None, timeout: int = 30) -> dict:
    """Descarga una sola página FHIR y retorna el bundle."""
    resp = requests.get(url, params=params, timeout=timeout)
    resp.raise_for_status()
    return resp.json()


def sync_resource_type(rtype: str, since: str | None, fhir_url: str,
                       page_size: int, conn, cursor) -> int:
    """
    Descarga y procesa un tipo de recurso página por página,
    haciendo commit después de cada página.
    """
    params = {"_count": page_size, "_sort": "_lastUpdated"}
    if since:
        params["_lastUpdated"] = f"gt{since}"

    extra = _deceased_filter_params(rtype)
    if extra:
        params.update(extra)

    url = f"{fhir_url}/{rtype}"
    page = 1
    count = 0

    while url:
        try:
            bundle = fetch_page(url, params if page == 1 else None)
        except Exception as e:
            log.error("Error consultando %s página %d: %s", rtype, page, e)
            raise

        entries = bundle.get("entry", [])
        resources = [e.get("resource", {}) for e in entries if e.get("resource")]

        log.info("  %s — página %d: %d recursos", rtype, page, len(resources))

        for resource in resources:
            if rtype == "Patient":
                result = _get_or_create_patient(cursor, resource)
                if result:
                    count += 1
            else:
                pat_ext_id = _patient_ref(resource)
                if not pat_ext_id:
                    continue
                cursor.execute(
                    f"SELECT id FROM {TBL_PATIENTS} WHERE external_id=%s",
                    (pat_ext_id,)
                )
                row = cursor.fetchone()
                if not row:
                    continue
                _upsert_clinical(cursor, resource, row[0])
                count += 1

        conn.commit()

        url = None
        page += 1
        for link in bundle.get("link", []):
            if link.get("relation") == "next":
                url = link.get("url")
                break

    return count


# ── Helpers de mapeo FHIR ─────────────────────────────────────────────────────
# (idénticos a los de fhir_adapter.py, reusados desde ahí para no duplicar)

from app.fhir.fhir_adapter import (
    _gender, _date, _datetime, _name, _identifier,
    _code_display, _code_value, _code_system,
    _extract_ref_id, _patient_ref, _truncate,
    _extract_patient_extended,
)


def _deceased_filter_params(resource_type: str) -> dict | None:
    """
    Arma el filtro de fallecidos según lo que soporte el servidor de la
    clínica (definido en capabilities dentro del JSON de config).
    """
    if resource_type == "Patient":
        if CAPABILITIES.get("supports_deceased_filter"):
            return {"deceased:not": "true"}
        return None

    if CAPABILITIES.get("supports_chained_search"):
        return {"patient.deceased:not": "true"}
    return None



def _get_or_create_patient(cursor, resource: dict) -> str | None:
    """Retorna el internal_id del paciente, creándolo si no existe."""
    ext_id = resource.get("id")
    if not ext_id:
        return None

    cursor.execute(
        f"SELECT id FROM {TBL_PATIENTS} WHERE external_id = %s", (ext_id,)
    )
    row = cursor.fetchone()
    if row:
        return row[0]

    internal_id = str(uuid.uuid4())
    first, last = _name(resource.get("name", []))
    extended    = _extract_patient_extended(resource)

    ward = bed_number = admission_date = None
    for ext in resource.get("extension", []):
        url = ext.get("url", "")
        if url == EXTENSION_URLS.get("ward"):
            ward = ext.get("valueString")
        elif url == EXTENSION_URLS.get("bed_number"):
            bed_number = ext.get("valueString")
        elif url == EXTENSION_URLS.get("admission_date"):
            admission_date = _datetime(ext.get("valueDateTime"))

    try:
        cursor.execute(
            f"""
            INSERT INTO {TBL_PATIENTS}
                (id, external_id, source_system,
                 first_name, last_name, birth_date, gender, local_id,
                 phone, address, marital_status, language, ethnicity,
                 deceased, deceased_date,
                 ward, bed_number, admission_date)
            VALUES (%s, %s, 'fhir', %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                internal_id, ext_id,
                first, last,
                _date(resource.get("birthDate")),
                _gender(resource.get("gender")),
                _identifier(resource.get("identifier", [])),
                extended["phone"], extended["address"],
                extended["marital_status"], extended["language"],
                extended["ethnicity"], extended["deceased"],
                extended["deceased_date"],
                ward, _truncate(bed_number, 20) if bed_number else None,
                admission_date,
            ),
        )
        _log_sync(cursor, "Patient", ext_id)
        log.info("  Paciente nuevo: %s %s", first, last)
        return internal_id

    except Exception as e:
        log.error("Error creando paciente %s: %s", ext_id, e)
        return None


def _upsert_clinical(cursor, resource: dict, internal_pat_id: str):
    """
    Inserta o actualiza un recurso clínico.
    Si ya existe en el log de sync, actualiza el registro en la DB.
    """
    rtype  = resource.get("resourceType")
    res_id = resource.get("id", str(uuid.uuid4()))

    if rtype not in _TABLE_BY_RTYPE:
        log.debug("Tipo de recurso no mapeado a tabla: %s", rtype)
        return

    cursor.execute(
        f"SELECT id FROM {TBL_SYNC_LOG} WHERE resource_type=%s AND resource_id=%s",
        (rtype, res_id)
    )
    already_exists = cursor.fetchone() is not None

    handlers = {
        "Encounter":          _upsert_encounter,
        "Condition":          _upsert_condition,
        "MedicationRequest":  _upsert_medication,
        "Observation":        _upsert_observation,
        "AllergyIntolerance": _upsert_allergy,
        "Procedure":          _upsert_procedure,
        "Immunization":       _upsert_immunization,
        "DiagnosticReport":   _upsert_diagnostic_report,
        "ImagingStudy":       _upsert_imaging_study,
        "CarePlan":           _upsert_care_plan,
        "CareTeam":           _upsert_care_team,
        "Device":             _upsert_device,
    }

    try:
        handlers[rtype](cursor, resource, res_id, internal_pat_id, already_exists)
        _log_sync(cursor, rtype, res_id)
    except Exception as e:
        log.error("Error %s %s: %s", rtype, res_id, e)


def _log_sync(cursor, rtype: str, res_id: str):
    cursor.execute(
        f"""
        INSERT INTO {TBL_SYNC_LOG} (id, resource_type, resource_id, status)
        VALUES (%s, %s, %s, 'success')
        ON DUPLICATE KEY UPDATE status='success', imported_at=NOW()
        """,
        (str(uuid.uuid4()), rtype, res_id)
    )


# ── Upserts por tipo ──────────────────────────────────────────────────────────

def _upsert_encounter(cursor, res, res_id, pat_id, exists):
    period    = res.get("period", {})
    types     = res.get("type", [])
    enc_type  = _code_display(types[0]) if types else ""
    enc_class = res.get("class", {})
    class_code = enc_class.get("code", "") if isinstance(enc_class, dict) else ""
    practitioner = ""
    for p in res.get("participant", []):
        d = p.get("individual", {}).get("display", "")
        if d and not practitioner:
            practitioner = d

    if exists:
        cursor.execute(
            f"""UPDATE {TBL_ENCOUNTERS} SET
               encounter_type=%s, status=%s, encounter_class=%s,
               start_date=%s, end_date=%s, reason=%s, practitioner_name=%s
               WHERE external_id=%s""",
            (_truncate(enc_type,100), _truncate(res.get("status"),50),
             _truncate(class_code,50),
             _datetime(period.get("start")), _datetime(period.get("end")),
             _code_display(res.get("reasonCode",[{}])[0]) if res.get("reasonCode") else "",
             _truncate(practitioner,200), res_id)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_ENCOUNTERS}
               (id,patient_id,external_id,source_system,
                encounter_type,status,start_date,end_date,
                reason,practitioner_name,encounter_class)
               VALUES (%s,%s,%s,'fhir',%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id,
             _truncate(enc_type,100), _truncate(res.get("status"),50),
             _datetime(period.get("start")), _datetime(period.get("end")),
             _code_display(res.get("reasonCode",[{}])[0]) if res.get("reasonCode") else "",
             _truncate(practitioner,200), _truncate(class_code,50))
        )


def _upsert_condition(cursor, res, res_id, pat_id, exists):
    clinical = res.get("clinicalStatus", {})
    severity = res.get("severity", {})
    asserter = res.get("asserter", {})
    vals = (
        _truncate(_code_value(res.get("code")),50),
        _truncate(_code_system(res.get("code")),100),
        _code_display(res.get("code")),
        _truncate(_code_display(clinical) or "active",50),
        _truncate(_code_display(severity),50),
        _truncate(asserter.get("display",""),200),
        _date(res.get("onsetDateTime") or res.get("recordedDate")),
        _date(res.get("abatementDateTime") or res.get("abatementDate")),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_CONDITIONS} SET
               code=%s,code_system=%s,description=%s,status=%s,
               severity=%s,recorded_by=%s,onset_date=%s,abatement_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_CONDITIONS}
               (id,patient_id,external_id,code,code_system,description,
                status,severity,recorded_by,onset_date,abatement_date)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_medication(cursor, res, res_id, pat_id, exists):
    med     = res.get("medicationCodeableConcept", {})
    dosage  = (res.get("dosageInstruction") or [{}])[0]
    timing  = dosage.get("timing", {}).get("code", {})
    freq    = _code_display(timing)
    req     = res.get("requester", {})
    vals = (
        _truncate(_code_value(med),50),
        _truncate(_code_system(med),100),
        _code_display(med),
        _truncate(dosage.get("text",""),200),
        _truncate(freq,100),
        _truncate(req.get("display",""),200),
        dosage.get("patientInstruction",""),
        _truncate(res.get("status","active"),50),
        _date(res.get("authoredOn")),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_MEDICATIONS} SET
               code=%s,code_system=%s,description=%s,dosage=%s,
               frequency=%s,prescriber=%s,instructions=%s,status=%s,start_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_MEDICATIONS}
               (id,patient_id,external_id,code,code_system,description,
                dosage,frequency,prescriber,instructions,status,start_date)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_observation(cursor, res, res_id, pat_id, exists):
    vq   = res.get("valueQuantity", {})
    vs   = _truncate(str(vq.get("value","")) if vq else res.get("valueString",""), 500)
    cats = res.get("category", [])
    cat  = _code_display(cats[0]) if cats else ""
    interps = res.get("interpretation", [])
    interp  = _code_display(interps[0]) if interps else ""
    vh = vl = ""
    for comp in res.get("component", []):
        cn = _code_display(comp.get("code",{})).lower()
        cv = str(comp.get("valueQuantity",{}).get("value",""))
        if "systolic" in cn:   vh = _truncate(cv,100)
        elif "diastolic" in cn: vl = _truncate(cv,100)

    vals = (
        _truncate(_code_value(res.get("code")),50),
        _truncate(_code_system(res.get("code")),100),
        _truncate(_code_display(res.get("code")) or cat, 500),
        vs, vh, vl,
        _truncate(vq.get("unit",""),50),
        _truncate(interp,50),
        _truncate(cat,100),
        _truncate(res.get("status"),50),
        _datetime(res.get("effectiveDateTime")),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_OBSERVATIONS} SET
               code=%s,code_system=%s,description=%s,value=%s,
               value_high=%s,value_low=%s,unit=%s,interpretation=%s,
               category=%s,status=%s,effective_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_OBSERVATIONS}
               (id,patient_id,external_id,code,code_system,description,
                value,value_high,value_low,unit,interpretation,category,
                status,effective_date)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_allergy(cursor, res, res_id, pat_id, exists):
    clinical  = res.get("clinicalStatus", {})
    reactions = res.get("reaction", [])
    rx_text   = "; ".join(
        _code_display(m) for r in reactions
        for m in r.get("manifestation", []) if _code_display(m)
    )
    recorder = res.get("recorder", {})
    vals = (
        _truncate(_code_value(res.get("code")),50),
        _truncate(_code_system(res.get("code")),100),
        _code_display(res.get("code")),
        _truncate(res.get("criticality",""),50),
        _truncate(_code_display(clinical) or "active",50),
        _date(res.get("onsetDateTime")),
        rx_text,
        _date(res.get("lastOccurrence")),
        _truncate(recorder.get("display",""),200),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_ALLERGIES} SET
               code=%s,code_system=%s,description=%s,severity=%s,
               status=%s,onset_date=%s,reaction=%s,
               last_occurrence=%s,recorded_by=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_ALLERGIES}
               (id,patient_id,external_id,code,code_system,description,
                severity,status,onset_date,reaction,last_occurrence,recorded_by)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_procedure(cursor, res, res_id, pat_id, exists):
    performed  = res.get("performedDateTime") or res.get("performedPeriod",{}).get("start")
    performers = res.get("performer", [])
    performer  = performers[0].get("actor",{}).get("display","") if performers else ""
    body_sites = res.get("bodySite", [])
    body_site  = _code_display(body_sites[0]) if body_sites else ""
    reasons    = res.get("reasonCode", [])
    reason     = _code_display(reasons[0]) if reasons else ""
    vals = (
        _truncate(_code_value(res.get("code")),50),
        _truncate(_code_system(res.get("code")),100),
        _code_display(res.get("code")),
        _truncate(res.get("status",""),50),
        _datetime(performed),
        _truncate(performer,200),
        _truncate(reason,500),
        _truncate(body_site,200),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_PROCEDURES} SET
               code=%s,code_system=%s,description=%s,status=%s,
               performed_date=%s,performer=%s,reason=%s,body_site=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_PROCEDURES}
               (id,patient_id,external_id,code,code_system,description,
                status,performed_date,performer,reason,body_site)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_immunization(cursor, res, res_id, pat_id, exists):
    performers = res.get("performer", [])
    performer  = performers[0].get("actor",{}).get("display","") if performers else ""
    vals = (
        _truncate(_code_value(res.get("vaccineCode",{})),50),
        _truncate(_code_system(res.get("vaccineCode",{})),100),
        _code_display(res.get("vaccineCode",{})),
        _truncate(res.get("status",""),50),
        _datetime(res.get("occurrenceDateTime")),
        _truncate(res.get("lotNumber",""),100),
        _truncate(res.get("manufacturer",{}).get("display",""),200),
        _truncate(_code_display(res.get("site",{})),100),
        _truncate(_code_display(res.get("route",{})),100),
        _truncate(performer,200),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_IMMUNIZATIONS} SET
               code=%s,code_system=%s,description=%s,status=%s,
               occurrence_date=%s,lot_number=%s,manufacturer=%s,
               site=%s,route=%s,performer=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_IMMUNIZATIONS}
               (id,patient_id,external_id,code,code_system,description,
                status,occurrence_date,lot_number,manufacturer,site,route,performer)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_diagnostic_report(cursor, res, res_id, pat_id, exists):
    cats       = res.get("category", [])
    category   = _code_display(cats[0]) if cats else ""
    performers = res.get("performer", [])
    performer  = performers[0].get("display","") if performers else ""
    conclusions = res.get("conclusionCode", [])
    conclusion  = _code_display(conclusions[0]) if conclusions else res.get("conclusion","")
    vals = (
        _truncate(_code_value(res.get("code")),50),
        _truncate(_code_system(res.get("code")),100),
        _code_display(res.get("code")),
        _truncate(category,100),
        _truncate(res.get("status",""),50),
        _datetime(res.get("effectiveDateTime")),
        _datetime(res.get("issued")),
        _truncate(performer,200),
        _truncate(conclusion,500) if conclusion else "",
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_DIAG_REPORTS} SET
               code=%s,code_system=%s,description=%s,category=%s,
               status=%s,effective_date=%s,issued_date=%s,
               performer=%s,conclusion=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_DIAG_REPORTS}
               (id,patient_id,external_id,code,code_system,description,
                category,status,effective_date,issued_date,performer,conclusion)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_imaging_study(cursor, res, res_id, pat_id, exists):
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
    vals = (
        _truncate(", ".join(modalities),50),
        _truncate(res.get("description",""),500),
        _truncate(res.get("status",""),50),
        _datetime(res.get("started")),
        len(series), instances,
        _truncate(body_site,200),
        _truncate(referrer,200),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_IMAGING} SET
               modality=%s,description=%s,status=%s,started_date=%s,
               number_series=%s,number_instances=%s,body_site=%s,referrer=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_IMAGING}
               (id,patient_id,external_id,modality,description,status,
                started_date,number_series,number_instances,body_site,referrer)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_care_plan(cursor, res, res_id, pat_id, exists):
    cats     = res.get("category", [])
    category = _code_display(cats[0]) if cats else ""
    period   = res.get("period", {})
    vals = (
        _truncate(res.get("title",""),300),
        res.get("description",""),
        _truncate(res.get("status",""),50),
        _truncate(res.get("intent",""),50),
        _truncate(category,200),
        _datetime(period.get("start")),
        _datetime(period.get("end")),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_CARE_PLANS} SET
               title=%s,description=%s,status=%s,intent=%s,
               category=%s,start_date=%s,end_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_CARE_PLANS}
               (id,patient_id,external_id,title,description,
                status,intent,category,start_date,end_date)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


def _upsert_care_team(cursor, res, res_id, pat_id, exists):
    cats     = res.get("category", [])
    category = _code_display(cats[0]) if cats else ""
    period   = res.get("period", {})

    if exists:
        cursor.execute(
            f"""UPDATE {TBL_CARE_TEAMS} SET
               name=%s,status=%s,category=%s,start_date=%s,end_date=%s
               WHERE external_id=%s""",
            (_truncate(res.get("name",""),300),
             _truncate(res.get("status",""),50),
             _truncate(category,200),
             _datetime(period.get("start")),
             _datetime(period.get("end")),
             res_id)
        )
        cursor.execute(f"SELECT id FROM {TBL_CARE_TEAMS} WHERE external_id=%s", (res_id,))
        care_team_id = cursor.fetchone()[0]
        cursor.execute(
            f"DELETE FROM {TBL_CT_MEMBERS} WHERE care_team_id=%s", (care_team_id,)
        )
    else:
        care_team_id = str(uuid.uuid4())
        cursor.execute(
            f"""INSERT INTO {TBL_CARE_TEAMS}
               (id,patient_id,external_id,name,status,category,start_date,end_date)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
            (care_team_id, pat_id, res_id,
             _truncate(res.get("name",""),300),
             _truncate(res.get("status",""),50),
             _truncate(category,200),
             _datetime(period.get("start")),
             _datetime(period.get("end")))
        )

    for participant in res.get("participant", []):
        roles  = participant.get("role", [])
        role   = _code_display(roles[0]) if roles else ""
        member = participant.get("member", {})
        m_ref  = member.get("reference","")
        m_type = m_ref.split("/")[0] if m_ref else ""
        cursor.execute(
            f"""INSERT INTO {TBL_CT_MEMBERS}
               (id,care_team_id,patient_id,role,member_name,member_type)
               VALUES (%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), care_team_id, pat_id,
             _truncate(role,200),
             _truncate(member.get("display",""),200),
             _truncate(m_type,100))
        )


def _upsert_device(cursor, res, res_id, pat_id, exists):
    udi_carriers = res.get("udiCarrier", [])
    udi          = udi_carriers[0].get("deviceIdentifier","") if udi_carriers else ""
    device_name  = res.get("deviceName", [])
    description  = device_name[0].get("name","") if device_name else \
                   _code_display(res.get("type",{}))
    vals = (
        _truncate(_code_value(res.get("type",{})),50),
        _truncate(_code_system(res.get("type",{})),100),
        _truncate(description,500),
        _truncate(res.get("status",""),50),
        _truncate(res.get("manufacturer",""),200),
        _truncate(res.get("modelNumber",""),200),
        _truncate(res.get("lotNumber",""),100),
        _truncate(res.get("serialNumber",""),100),
        _date(res.get("expirationDate")),
        _truncate(udi,300),
    )
    if exists:
        cursor.execute(
            f"""UPDATE {TBL_DEVICES} SET
               code=%s,code_system=%s,description=%s,status=%s,
               manufacturer=%s,model=%s,lot_number=%s,serial_number=%s,
               expiration_date=%s,udi=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            f"""INSERT INTO {TBL_DEVICES}
               (id,patient_id,external_id,code,code_system,description,
                status,manufacturer,model,lot_number,serial_number,
                expiration_date,udi)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


# ── Loop principal ────────────────────────────────────────────────────────────

def sync_cycle():
    load_dotenv(Path(__file__).parent.parent.parent / '.env', override=True)
    fhir_url      = os.getenv('FHIR_BASE_URL', '').rstrip('/')
    sync_interval = int(os.getenv('FHIR_SYNC_INTERVAL_MINUTES', '5')) * 60
    page_size     = int(os.getenv('FHIR_PAGE_SIZE', '50'))

    if not fhir_url:
        log.error("FHIR_BASE_URL no configurada en .env")
        return sync_interval

    state = load_state()
    log.info("Iniciando ciclo de sincronización — Clínica: %s — FHIR: %s",
             CLINIC.get("clinic_id", "?"), fhir_url)

    try:
        conn   = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
    except Exception as e:
        log.error("Error conectando a MariaDB: %s", e)
        return

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

    for rtype in RESOURCE_TYPES:
        since = state.get(rtype)
        log.info("  %s — sincronizando desde %s", rtype, since or "inicio")

        try:
            count = sync_resource_type(rtype, since, fhir_url, page_size, conn, cursor)
            state[rtype] = now_iso
            save_state(state)
            log.info("  %s — completado: %d procesados", rtype, count)
        except Exception as e:
            log.error("  %s — error en sincronización: %s", rtype, e)
            continue

    cursor.close()
    conn.close()
    log.info("Ciclo completado. Próxima sincronización en %ds", sync_interval)
    return sync_interval


if __name__ == "__main__":
    initial_sync_interval = int(os.getenv('FHIR_SYNC_INTERVAL_MINUTES', '5')) * 60
    log.info("Sync service iniciado. Clínica: %s — Intervalo: %ds",
              CLINIC.get("clinic_id", "?"), initial_sync_interval)
    while True:
        try:
            sync_interval = sync_cycle()
        except Exception as e:
            log.error("Error inesperado en ciclo: %s", e)
            sync_interval = initial_sync_interval
        time.sleep(sync_interval)
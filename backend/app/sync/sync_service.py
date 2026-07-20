#!/usr/bin/env python3
"""
Servicio de sincronización FHIR R4 → MariaDB
=============================================
Consulta HAPI FHIR periódicamente usando _lastUpdated para traer
solo los recursos modificados desde la última sincronización.

Ejecutar como servicio systemd:
    python3 -m app.sync.sync_service
"""
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

FHIR_BASE_URL       = os.getenv('FHIR_BASE_URL', '').rstrip('/')
SYNC_INTERVAL_SECS  = int(os.getenv('FHIR_SYNC_INTERVAL_MINUTES', '5')) * 60
PAGE_SIZE           = int(os.getenv('FHIR_PAGE_SIZE', '50'))
STATE_FILE          = Path(__file__).parent.parent.parent / 'fhir_sync_state.json'

DB_CONFIG = {
    "host":     "localhost",
    "user":     os.getenv('DB_USER', 'admin'),
    "password": os.getenv('DB_PASSWORD', 'admin'),
    "database": os.getenv('DB_NAME', 'carer_record'),
}

# Tipos de recursos a sincronizar en orden de dependencia
RESOURCE_TYPES = [
    "Patient",
    "Encounter",
    "Condition",
    "MedicationRequest",
    "Observation",
    "AllergyIntolerance",
    "Procedure",
    "Immunization",
    "DiagnosticReport",
    "ImagingStudy",
    "CarePlan",
    "CareTeam",
    "Device",
]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [sync_service] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

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

def fetch_updated_resources(resource_type: str, since: str | None) -> list:
    """
    Descarga todos los recursos de un tipo actualizados después de `since`.
    Maneja paginación automáticamente.
    """
    params = {
        "_count":  PAGE_SIZE,
        "_sort":   "_lastUpdated",
    }
    if since:
        params["_lastUpdated"] = f"gt{since}"

    url      = f"{FHIR_BASE_URL}/{resource_type}"
    resources = []
    page      = 1

    while url:
        try:
            resp = requests.get(url, params=params if page == 1 else None,
                                timeout=30)
            resp.raise_for_status()
            bundle = resp.json()
        except Exception as e:
            log.error("Error consultando %s: %s", resource_type, e)
            break

        entries = bundle.get("entry", [])
        resources.extend(e.get("resource", {}) for e in entries
                         if e.get("resource"))

        log.info("  %s — página %d: %d recursos",
                 resource_type, page, len(entries))

        # Siguiente página
        url  = None
        page += 1
        for link in bundle.get("link", []):
            if link.get("relation") == "next":
                url = link.get("url")
                break

    return resources

# ── Importación incremental ───────────────────────────────────────────────────
# Reutiliza los helpers del fhir_adapter existente

from app.fhir.fhir_adapter import (
    _gender, _date, _datetime, _name, _identifier,
    _code_display, _code_value, _code_system,
    _extract_ref_id, _patient_ref, _truncate,
    _extract_patient_extended, EXTENSION_URLS,
)


def _get_or_create_patient(cursor, resource: dict) -> str | None:
    """Retorna el internal_id del paciente, creándolo si no existe."""
    ext_id = resource.get("id")
    if not ext_id:
        return None

    cursor.execute(
        "SELECT id FROM patients WHERE external_id = %s", (ext_id,)
    )
    row = cursor.fetchone()
    if row:
        return row[0]

    # Crear nuevo paciente
    internal_id = str(uuid.uuid4())
    first, last = _name(resource.get("name", []))
    extended    = _extract_patient_extended(resource)

    # Para sync incremental no tenemos el bundle completo,
    # así que la ubicación vendrá de las extensiones del recurso
    ward = bed_number = admission_date = None
    for ext in resource.get("extension", []):
        url = ext.get("url", "")
        if url == EXTENSION_URLS["ward"]:
            ward = ext.get("valueString")
        elif url == EXTENSION_URLS["bed_number"]:
            bed_number = ext.get("valueString")
        elif url == EXTENSION_URLS["admission_date"]:
            admission_date = _datetime(ext.get("valueDateTime"))

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
    Si ya existe en fhir_sync_log, actualiza el registro en la DB.
    """
    rtype  = resource.get("resourceType")
    res_id = resource.get("id", str(uuid.uuid4()))

    # Verificar si ya existe
    cursor.execute(
        "SELECT id FROM fhir_sync_log WHERE resource_type=%s AND resource_id=%s",
        (rtype, res_id)
    )
    already_exists = cursor.fetchone() is not None

    try:
        if rtype == "Encounter":
            _upsert_encounter(cursor, resource, res_id,
                              internal_pat_id, already_exists)
        elif rtype == "Condition":
            _upsert_condition(cursor, resource, res_id,
                              internal_pat_id, already_exists)
        elif rtype == "MedicationRequest":
            _upsert_medication(cursor, resource, res_id,
                               internal_pat_id, already_exists)
        elif rtype == "Observation":
            _upsert_observation(cursor, resource, res_id,
                                internal_pat_id, already_exists)
        elif rtype == "AllergyIntolerance":
            _upsert_allergy(cursor, resource, res_id,
                            internal_pat_id, already_exists)
        elif rtype == "Procedure":
            _upsert_procedure(cursor, resource, res_id,
                              internal_pat_id, already_exists)
        elif rtype == "Immunization":
            _upsert_immunization(cursor, resource, res_id,
                                 internal_pat_id, already_exists)
        elif rtype == "DiagnosticReport":
            _upsert_diagnostic_report(cursor, resource, res_id,
                                      internal_pat_id, already_exists)
        elif rtype == "ImagingStudy":
            _upsert_imaging_study(cursor, resource, res_id,
                                  internal_pat_id, already_exists)
        elif rtype == "CarePlan":
            _upsert_care_plan(cursor, resource, res_id,
                              internal_pat_id, already_exists)
        elif rtype == "CareTeam":
            _upsert_care_team(cursor, resource, res_id,
                              internal_pat_id, already_exists)
        elif rtype == "Device":
            _upsert_device(cursor, resource, res_id,
                           internal_pat_id, already_exists)

        _log_sync(cursor, rtype, res_id)

    except Exception as e:
        log.error("Error %s %s: %s", rtype, res_id, e)


def _log_sync(cursor, rtype: str, res_id: str):
    cursor.execute(
        """
        INSERT INTO fhir_sync_log (id, resource_type, resource_id, status)
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
            """UPDATE encounters SET
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
            """INSERT INTO encounters
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
            """UPDATE conditions SET
               code=%s,code_system=%s,description=%s,status=%s,
               severity=%s,recorded_by=%s,onset_date=%s,abatement_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO conditions
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
            """UPDATE medications SET
               code=%s,code_system=%s,description=%s,dosage=%s,
               frequency=%s,prescriber=%s,instructions=%s,status=%s,start_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO medications
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
            """UPDATE observations SET
               code=%s,code_system=%s,description=%s,value=%s,
               value_high=%s,value_low=%s,unit=%s,interpretation=%s,
               category=%s,status=%s,effective_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO observations
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
            """UPDATE allergies SET
               code=%s,code_system=%s,description=%s,severity=%s,
               status=%s,onset_date=%s,reaction=%s,
               last_occurrence=%s,recorded_by=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO allergies
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
            """UPDATE procedures SET
               code=%s,code_system=%s,description=%s,status=%s,
               performed_date=%s,performer=%s,reason=%s,body_site=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO procedures
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
            """UPDATE immunizations SET
               code=%s,code_system=%s,description=%s,status=%s,
               occurrence_date=%s,lot_number=%s,manufacturer=%s,
               site=%s,route=%s,performer=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO immunizations
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
            """UPDATE diagnostic_reports SET
               code=%s,code_system=%s,description=%s,category=%s,
               status=%s,effective_date=%s,issued_date=%s,
               performer=%s,conclusion=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO diagnostic_reports
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
            """UPDATE imaging_studies SET
               modality=%s,description=%s,status=%s,started_date=%s,
               number_series=%s,number_instances=%s,body_site=%s,referrer=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO imaging_studies
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
            """UPDATE care_plans SET
               title=%s,description=%s,status=%s,intent=%s,
               category=%s,start_date=%s,end_date=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO care_plans
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
            """UPDATE care_teams SET
               name=%s,status=%s,category=%s,start_date=%s,end_date=%s
               WHERE external_id=%s""",
            (_truncate(res.get("name",""),300),
             _truncate(res.get("status",""),50),
             _truncate(category,200),
             _datetime(period.get("start")),
             _datetime(period.get("end")),
             res_id)
        )
        cursor.execute("SELECT id FROM care_teams WHERE external_id=%s", (res_id,))
        care_team_id = cursor.fetchone()[0]
        cursor.execute(
            "DELETE FROM care_team_members WHERE care_team_id=%s", (care_team_id,)
        )
    else:
        care_team_id = str(uuid.uuid4())
        cursor.execute(
            """INSERT INTO care_teams
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
            """INSERT INTO care_team_members
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
            """UPDATE devices SET
               code=%s,code_system=%s,description=%s,status=%s,
               manufacturer=%s,model=%s,lot_number=%s,serial_number=%s,
               expiration_date=%s,udi=%s
               WHERE external_id=%s""",
            vals + (res_id,)
        )
    else:
        cursor.execute(
            """INSERT INTO devices
               (id,patient_id,external_id,code,code_system,description,
                status,manufacturer,model,lot_number,serial_number,
                expiration_date,udi)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (str(uuid.uuid4()), pat_id, res_id) + vals
        )


# ── Loop principal ────────────────────────────────────────────────────────────

def sync_cycle():
    if not FHIR_BASE_URL:
        log.error("FHIR_BASE_URL no configurada en .env")
        return

    state = load_state()
    log.info("Iniciando ciclo de sincronización — FHIR: %s", FHIR_BASE_URL)

    try:
        conn   = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
    except Exception as e:
        log.error("Error conectando a MariaDB: %s", e)
        return

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

    for rtype in RESOURCE_TYPES:
        since     = state.get(rtype)
        resources = fetch_updated_resources(rtype, since)

        if not resources:
            log.info("  %s — sin cambios", rtype)
            state[rtype] = now_iso
            continue

        log.info("  %s — procesando %d recursos", rtype, len(resources))
        count = 0

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
                    "SELECT id FROM patients WHERE external_id=%s", (pat_ext_id,)
                )
                row = cursor.fetchone()
                if not row:
                    log.debug("Paciente %s no encontrado, omitiendo %s",
                              pat_ext_id, rtype)
                    continue
                _upsert_clinical(cursor, resource, row[0])
                count += 1

        conn.commit()
        state[rtype] = now_iso
        log.info("  %s — %d procesados", rtype, count)

    cursor.close()
    conn.close()
    save_state(state)
    log.info("Ciclo completado. Próxima sincronización en %ds", SYNC_INTERVAL_SECS)


if __name__ == "__main__":
    log.info("Sync service iniciado. Intervalo: %ds", SYNC_INTERVAL_SECS)
    while True:
        try:
            sync_cycle()
        except Exception as e:
            log.error("Error inesperado en ciclo: %s", e)
        time.sleep(SYNC_INTERVAL_SECS)
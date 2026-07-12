"""
Adaptador FHIR R4 Completo
==========================
Lee bundles JSON generados por Synthea e importa pacientes,
encuentros, condiciones, medicamentos, observaciones y alergias
a la base de datos normalizada de Carer Record.

Uso:
    python fhir_adapter.py --input ./integration/test_data/fhir/

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
    """Extrae texto legible de un CodeableConcept FHIR."""
    if not codeable_concept:
        return ""
    if "text" in codeable_concept:
        return codeable_concept["text"]
    for coding in codeable_concept.get("coding", []):
        if "display" in coding:
            return coding["display"]
    return ""


def _code_value(codeable_concept: dict) -> str:
    """Extrae el código (ej. SNOMED, LOINC) de un CodeableConcept FHIR."""
    if not codeable_concept:
        return ""
    for coding in codeable_concept.get("coding", []):
        if "code" in coding:
            return coding["code"]
    return ""


def _code_system(codeable_concept: dict) -> str:
    """Extrae el sistema de codificación (ej. http://snomed.info/sct)."""
    if not codeable_concept:
        return ""
    for coding in codeable_concept.get("coding", []):
        if "system" in coding:
            return coding["system"]
    return ""


def _extract_ref_id(reference_str: str) -> str:
    """Extrae el UUID de referencias FHIR como 'urn:uuid:123' o 'Patient/123'."""
    if not reference_str:
        return ""
    return reference_str.split(":")[-1].split("/")[-1]


def _patient_ref(resource: dict) -> str:
    """Extrae la referencia al paciente desde subject o patient."""
    ref = resource.get("subject", resource.get("patient", {}))
    return _extract_ref_id(ref.get("reference", ""))


# ── Importación ───────────────────────────────────────────────────────────────

def import_bundle(conn, bundle_path: Path) -> dict:
    stats = {
        "patients":     0,
        "encounters":   0,
        "conditions":   0,
        "medications":  0,
        "observations": 0,
        "allergies":    0,
        "skipped":      0,
        "errors":       0,
    }
    cursor = conn.cursor()

    with open(bundle_path, encoding="utf-8") as f:
        bundle = json.load(f)

    entries = bundle.get("entry", [])

    # Caché: external_id FHIR → id interno MariaDB
    patient_map = {}

    # ── PASO 1: Pacientes ──────────────────────────────────────────────────
    for entry in entries:
        res   = entry.get("resource", {})
        rtype = res.get("resourceType")

        if rtype != "Patient":
            continue

        ext_id = res.get("id")

        # Verificar si ya existe en fhir_sync_log
        cursor.execute(
            "SELECT id FROM fhir_sync_log WHERE resource_type = 'Patient' AND resource_id = %s",
            (ext_id,),
        )
        existing_log = cursor.fetchone()

        # Buscar id interno por external_id
        cursor.execute(
            "SELECT id FROM patients WHERE external_id = %s",
            (ext_id,),
        )
        existing_patient = cursor.fetchone()

        if existing_patient:
            patient_map[ext_id] = existing_patient[0]
            if existing_log:
                stats["skipped"] += 1
            continue

        internal_id       = str(uuid.uuid4())
        first, last       = _name(res.get("name", []))

        try:
            cursor.execute(
                """
                INSERT INTO patients
                    (id, external_id, source_system,
                     first_name, last_name, birth_date, gender, local_id)
                VALUES (%s, %s, 'fhir', %s, %s, %s, %s, %s)
                """,
                (
                    internal_id,
                    ext_id,
                    first,
                    last,
                    _date(res.get("birthDate")),
                    _gender(res.get("gender")),
                    _identifier(res.get("identifier", [])),
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

    # ── PASO 2: Recursos clínicos ──────────────────────────────────────────
    for entry in entries:
        res   = entry.get("resource", {})
        rtype = res.get("resourceType")
        res_id = res.get("id", str(uuid.uuid4()))

        if rtype == "Patient":
            continue

        if rtype not in ("Encounter", "Condition", "MedicationRequest",
                         "Observation", "AllergyIntolerance"):
            continue

        pat_ext_id      = _patient_ref(res)
        internal_pat_id = patient_map.get(pat_ext_id)

        if not internal_pat_id:
            continue

        # Verificar duplicado en fhir_sync_log
        cursor.execute(
            "SELECT id FROM fhir_sync_log WHERE resource_type = %s AND resource_id = %s",
            (rtype, res_id),
        )
        if cursor.fetchone():
            stats["skipped"] += 1
            continue

        try:
            if rtype == "Encounter":
                period = res.get("period", {})
                types  = res.get("type", [])
                encounter_type = _code_display(types[0]) if types else ""

                cursor.execute(
                    """
                    INSERT INTO encounters
                        (id, patient_id, external_id, source_system,
                         encounter_type, status, start_date, end_date, reason)
                    VALUES (%s, %s, %s, 'fhir', %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()),
                        internal_pat_id,
                        res_id,
                        encounter_type,
                        res.get("status"),
                        _datetime(period.get("start")),
                        _datetime(period.get("end")),
                        _code_display(res.get("reasonCode", [{}])[0])
                        if res.get("reasonCode") else "",
                    ),
                )
                stats["encounters"] += 1

            elif rtype == "Condition":
                clinical = res.get("clinicalStatus", {})

                cursor.execute(
                    """
                    INSERT INTO conditions
                        (id, patient_id, external_id,
                         code, code_system, description,
                         status, onset_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()),
                        internal_pat_id,
                        res_id,
                        _code_value(res.get("code")),
                        _code_system(res.get("code")),
                        _code_display(res.get("code")),
                        _code_display(clinical) or "active",
                        _date(res.get("onsetDateTime") or res.get("recordedDate")),
                    ),
                )
                stats["conditions"] += 1

            elif rtype == "MedicationRequest":
                med_concept = res.get("medicationCodeableConcept", {})

                cursor.execute(
                    """
                    INSERT INTO medications
                        (id, patient_id, external_id,
                         code, code_system, description,
                         status, start_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()),
                        internal_pat_id,
                        res_id,
                        _code_value(med_concept),
                        _code_system(med_concept),
                        _code_display(med_concept),
                        res.get("status", "active"),
                        _date(res.get("authoredOn")),
                    ),
                )
                stats["medications"] += 1

            elif rtype == "Observation":
                value_qty = res.get("valueQuantity", {})
                value_str = str(value_qty.get("value", "")) if value_qty else ""
                value_str = value_str or res.get("valueString", "")
                categories = res.get("category", [])
                category   = _code_display(categories[0]) if categories else ""

                cursor.execute(
                    """
                    INSERT INTO observations
                        (id, patient_id, external_id,
                         code, code_system, description,
                         value, unit, status, effective_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()),
                        internal_pat_id,
                        res_id,
                        _code_value(res.get("code")),
                        _code_system(res.get("code")),
                        _code_display(res.get("code")) or category,
                        value_str[:200],
                        value_qty.get("unit", ""),
                        res.get("status"),
                        _datetime(res.get("effectiveDateTime")),
                    ),
                )
                stats["observations"] += 1

            elif rtype == "AllergyIntolerance":
                clinical = res.get("clinicalStatus", {})

                cursor.execute(
                    """
                    INSERT INTO allergies
                        (id, patient_id, external_id,
                         code, code_system, description,
                         severity, status, onset_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        str(uuid.uuid4()),
                        internal_pat_id,
                        res_id,
                        _code_value(res.get("code")),
                        _code_system(res.get("code")),
                        _code_display(res.get("code")),
                        res.get("criticality", ""),
                        _code_display(clinical) or "active",
                        _date(res.get("onsetDateTime")),
                    ),
                )
                stats["allergies"] += 1

            # Registrar en fhir_sync_log
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
    total = {k: 0 for k in ("patients", "encounters", "conditions",
                             "medications", "observations", "allergies",
                             "skipped", "errors")}

    for bundle_path in sorted(bundles):
        log.info("Procesando: %s", bundle_path.name)
        stats = import_bundle(conn, bundle_path)
        for k in total:
            total[k] += stats[k]

    conn.close()

    log.info("\n=== Importación completa ===")
    for k, v in total.items():
        log.info("  %-15s: %d", k.capitalize(), v)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Importador FHIR R4 → MariaDB")
    parser.add_argument(
        "--input", required=True,
        help="Directorio con bundles JSON de Synthea (ej: ./integration/test_data/fhir/)",
    )
    args = parser.parse_args()
    run(args.input)
"""
Adaptador FHIR R4
=================
Lee bundles JSON generados por Synthea e importa pacientes
a la base de datos normalizada de Carer Record.

Uso:
    python fhir_adapter.py --input ./synthea_output/fhir/

Requisitos (en la Raspberry Pi):
    pip install mysql-connector-python --break-system-packages
"""

import json
import uuid
import argparse
import logging
from pathlib import Path
from datetime import datetime

import mysql.connector

# ── Configuración ────────────────────────────────────────────────────────────

DB_CONFIG = {
    "host":     "localhost",
    "user":     "carer_user",
    "password": "CAMBIAR_EN_PRODUCCION",
    "database": "carer_record",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

# ── Helpers de mapeo FHIR → modelo interno ───────────────────────────────────

def _gender(fhir_gender: str | None) -> str:
    return {"male": "male", "female": "female"}.get(fhir_gender or "", "unknown")


def _date(fhir_date: str | None):
    """Convierte '1990-03-15' a objeto date; retorna None si es inválido."""
    if not fhir_date:
        return None
    try:
        return datetime.strptime(fhir_date[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def _name(fhir_names: list) -> tuple[str, str]:
    """Extrae (first_name, last_name) del arreglo HumanName de FHIR."""
    for n in fhir_names:
        given  = " ".join(n.get("given", []))
        family = n.get("family", "")
        if given or family:
            return given, family
    return "", ""


def _identifier(identifiers: list, system_hint: str = "") -> str | None:
    """Busca un identificador local (RUT u otro) en la lista FHIR."""
    for ident in identifiers:
        system = ident.get("system", "")
        if system_hint and system_hint.lower() in system.lower():
            return ident.get("value")
    # Si no hay coincidencia exacta, devuelve el primero disponible
    return identifiers[0].get("value") if identifiers else None

# ── Lógica principal de importación ──────────────────────────────────────────

def import_bundle(conn, bundle_path: Path) -> dict:
    """
    Procesa un bundle FHIR JSON de Synthea.
    Retorna un resumen con conteos de éxitos y errores.
    """
    stats = {"patients": 0, "skipped": 0, "errors": 0}
    cursor = conn.cursor()

    with open(bundle_path, encoding="utf-8") as f:
        bundle = json.load(f)

    entries = bundle.get("entry", [])

    for entry in entries:
        resource = entry.get("resource", {})
        rtype = resource.get("resourceType")

        if rtype != "Patient":
            # Por ahora solo importamos pacientes.
            # Ampliar aquí para Encounter, Observation, etc.
            continue

        resource_id = resource.get("id", str(uuid.uuid4()))

        # Verificar si ya fue importado
        cursor.execute(
            "SELECT id FROM fhir_sync_log WHERE resource_type = %s AND resource_id = %s",
            ("Patient", resource_id),
        )
        if cursor.fetchone():
            log.debug("Paciente %s ya importado, omitiendo.", resource_id)
            stats["skipped"] += 1
            continue

        try:
            first_name, last_name = _name(resource.get("name", []))
            patient_id = str(uuid.uuid4())

            cursor.execute(
                """
                INSERT INTO patients
                    (id, external_id, source_system,
                     first_name, last_name, birth_date, gender, local_id)
                VALUES (%s, %s, 'fhir', %s, %s, %s, %s, %s)
                """,
                (
                    patient_id,
                    resource_id,
                    first_name,
                    last_name,
                    _date(resource.get("birthDate")),
                    _gender(resource.get("gender")),
                    _identifier(resource.get("identifier", [])),
                ),
            )

            cursor.execute(
                """
                INSERT INTO fhir_sync_log
                    (id, resource_type, resource_id, bundle_file, status)
                VALUES (%s, 'Patient', %s, %s, 'success')
                """,
                (str(uuid.uuid4()), resource_id, bundle_path.name),
            )

            conn.commit()
            stats["patients"] += 1
            log.info("✓ Paciente importado: %s %s", first_name, last_name)

        except Exception as exc:
            conn.rollback()
            stats["errors"] += 1
            log.error("✗ Error importando paciente %s: %s", resource_id, exc)

            cursor.execute(
                """
                INSERT IGNORE INTO fhir_sync_log
                    (id, resource_type, resource_id, bundle_file, status, error_detail)
                VALUES (%s, 'Patient', %s, %s, 'error', %s)
                """,
                (str(uuid.uuid4()), resource_id, bundle_path.name, str(exc)),
            )
            conn.commit()

    cursor.close()
    return stats


def run(input_dir: str):
    fhir_path = Path(input_dir)
    bundles   = list(fhir_path.glob("*.json"))

    if not bundles:
        log.warning("No se encontraron archivos JSON en %s", fhir_path)
        return

    log.info("Conectando a MariaDB...")
    conn = mysql.connector.connect(**DB_CONFIG)
    log.info("Conexión exitosa. Procesando %d archivos...", len(bundles))

    total = {"patients": 0, "skipped": 0, "errors": 0}

    for bundle_path in sorted(bundles):
        log.info("Procesando: %s", bundle_path.name)
        stats = import_bundle(conn, bundle_path)
        for k in total:
            total[k] += stats[k]

    conn.close()

    log.info(
        "\n=== Importación completa ===\n"
        "  Pacientes importados : %d\n"
        "  Omitidos (ya existen): %d\n"
        "  Errores              : %d",
        total["patients"], total["skipped"], total["errors"],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Importador FHIR R4 → MariaDB")
    parser.add_argument(
        "--input", required=True,
        help="Directorio con bundles JSON de Synthea (ej: ./output/fhir/)"
    )
    args = parser.parse_args()
    run(args.input)

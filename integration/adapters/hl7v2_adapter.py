"""
Adaptador HL7v2 (MLLP listener)
================================
Escucha mensajes HL7v2 ADT en el protocolo MLLP (el estándar de
transporte para HL7v2 sobre TCP), parsea los campos relevantes y
normaliza a la tabla `patients` de Carer Record.

También incluye un generador de mensajes de prueba para desarrollo
local (sin necesitar un sistema hospitalario real).

Uso — listener real:
    python hl7v2_adapter.py listen --port 2575

Uso — generar mensajes de prueba desde CSV de Synthea:
    python hl7v2_adapter.py generate --csv ./output/csv/patients.csv

Requisitos:
    pip install hl7apy mysql-connector-python --break-system-packages
"""

import csv
import logging
import socket
import socketserver
import threading
import uuid
import argparse
from datetime import datetime, date

import mysql.connector

# ── Configuración ─────────────────────────────────────────────────────────────

DB_CONFIG = {
    "host":     "localhost",
    "user":     "carer_user",
    "password": "CAMBIAR_EN_PRODUCCION",
    "database": "carer_record",
}

MLLP_START = b"\x0b"   # Vertical Tab — inicio de bloque MLLP
MLLP_END   = b"\x1c\r" # FS + CR     — fin de bloque MLLP

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

# ── Parser HL7v2 minimalista ──────────────────────────────────────────────────
# hl7apy es la librería completa, pero para los segmentos que usamos
# un parser manual es más fácil de entender y depurar.

class HL7v2Message:
    """
    Parsea un mensaje HL7v2 de texto plano.
    Acceso a campos: msg['PID'][5][1] (segmento PID, campo 5, componente 1)
    """

    def __init__(self, raw: str):
        self.raw      = raw
        self.segments = {}
        self._parse(raw)

    def _parse(self, raw: str):
        for line in raw.strip().splitlines():
            if not line:
                continue
            parts = line.split("|")
            seg_name = parts[0]
            # Guardar todos los campos (incluye sub-componentes con ^)
            self.segments[seg_name] = [f.split("^") for f in parts]

    def get(self, segment: str, field: int, component: int = 0, default="") -> str:
        seg = self.segments.get(segment)
        if not seg or field >= len(seg):
            return default
        components = seg[field]
        if component >= len(components):
            return default
        return components[component] or default


def _parse_hl7_date(hl7_date: str) -> date | None:
    """Convierte '19900315' o '199003' a objeto date."""
    hl7_date = hl7_date.strip()
    for fmt in ("%Y%m%d", "%Y%m"):
        try:
            return datetime.strptime(hl7_date[:len(fmt.replace("%Y","2006").replace("%m","01").replace("%d","01"))], fmt).date()
        except ValueError:
            continue
    return None


def _gender_from_hl7(code: str) -> str:
    return {"M": "male", "F": "female"}.get(code.upper(), "unknown")


# ── Base de datos ─────────────────────────────────────────────────────────────

def save_raw_message(conn, msg_type: str, raw: str) -> str:
    """Guarda el mensaje crudo en hl7v2_raw_messages y retorna su ID."""
    msg_id = str(uuid.uuid4())
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO hl7v2_raw_messages (id, message_type, raw_message)
           VALUES (%s, %s, %s)""",
        (msg_id, msg_type, raw),
    )
    conn.commit()
    cursor.close()
    return msg_id


def normalize_and_save(conn, msg: HL7v2Message, raw_id: str):
    """
    Extrae campos del segmento PID (Patient Identification) y
    guarda/actualiza el paciente en la tabla normalizada.
    """
    cursor = conn.cursor()

    # PID-3: Patient Identifier List (usamos el primero)
    external_id = msg.get("PID", 3, 0)
    # PID-5: Patient Name [Last^First^Middle]
    last_name   = msg.get("PID", 5, 0)
    first_name  = msg.get("PID", 5, 1)
    # PID-7: Date of Birth (YYYYMMDD)
    birth_date  = _parse_hl7_date(msg.get("PID", 7, 0))
    # PID-8: Sex
    gender      = _gender_from_hl7(msg.get("PID", 8, 0))

    # PV1: Patient Visit — ubicación
    # PV1-3: Assigned Patient Location [Ward^Room^Bed]
    ward        = msg.get("PV1", 3, 0)
    bed_number  = msg.get("PV1", 3, 2)
    # PV1-44: Admit Date
    admit_raw   = msg.get("PV1", 44, 0)
    admit_date  = _parse_hl7_date(admit_raw) if admit_raw else None

    # Verificar si el paciente ya existe por external_id
    cursor.execute(
        "SELECT id FROM patients WHERE external_id = %s AND source_system = 'hl7v2'",
        (external_id,),
    )
    row = cursor.fetchone()

    try:
        if row:
            # Actualizar paciente existente (ADT^A08 — update)
            patient_id = row[0]
            cursor.execute(
                """UPDATE patients SET
                       first_name = %s, last_name = %s, birth_date = %s,
                       gender = %s, ward = %s, bed_number = %s,
                       admission_date = %s, updated_at = CURRENT_TIMESTAMP
                   WHERE id = %s""",
                (first_name, last_name, birth_date, gender,
                 ward or None, bed_number or None, admit_date, patient_id),
            )
            log.info("↺ Paciente actualizado: %s %s", first_name, last_name)
        else:
            # Crear paciente nuevo (ADT^A01 — admisión)
            patient_id = str(uuid.uuid4())
            cursor.execute(
                """INSERT INTO patients
                       (id, external_id, source_system,
                        first_name, last_name, birth_date, gender,
                        ward, bed_number, admission_date)
                   VALUES (%s, %s, 'hl7v2', %s, %s, %s, %s, %s, %s, %s)""",
                (patient_id, external_id, first_name, last_name,
                 birth_date, gender, ward or None, bed_number or None, admit_date),
            )
            log.info("✓ Paciente creado: %s %s", first_name, last_name)

        # Marcar mensaje crudo como procesado
        cursor.execute(
            "UPDATE hl7v2_raw_messages SET processed = TRUE, patient_id = %s WHERE id = %s",
            (patient_id, raw_id),
        )
        conn.commit()

    except Exception as exc:
        conn.rollback()
        cursor.execute(
            "UPDATE hl7v2_raw_messages SET error_detail = %s WHERE id = %s",
            (str(exc), raw_id),
        )
        conn.commit()
        log.error("✗ Error normalizando mensaje %s: %s", raw_id, exc)
    finally:
        cursor.close()


# ── MLLP Listener ─────────────────────────────────────────────────────────────

class MLLPHandler(socketserver.BaseRequestHandler):
    """
    Maneja una conexión TCP entrante con protocolo MLLP.
    Cada mensaje se delimitado por VT (inicio) y FS+CR (fin).
    """

    def handle(self):
        conn = mysql.connector.connect(**DB_CONFIG)
        log.info("Conexión entrante de %s", self.client_address)

        buffer = b""
        try:
            while True:
                chunk = self.request.recv(4096)
                if not chunk:
                    break
                buffer += chunk

                while MLLP_START in buffer and MLLP_END in buffer:
                    start = buffer.index(MLLP_START) + 1
                    end   = buffer.index(MLLP_END)
                    raw_bytes = buffer[start:end]
                    buffer    = buffer[end + len(MLLP_END):]

                    raw_str  = raw_bytes.decode("utf-8", errors="replace")
                    msg      = HL7v2Message(raw_str)
                    msg_type = msg.get("MSH", 9, 0) + "^" + msg.get("MSH", 9, 1)

                    log.info("Mensaje recibido: %s", msg_type)
                    raw_id = save_raw_message(conn, msg_type, raw_str)

                    # Procesar solo admisiones y actualizaciones
                    if msg_type.startswith("ADT"):
                        normalize_and_save(conn, msg, raw_id)

                    # Responder ACK al sistema origen
                    ack = self._build_ack(msg)
                    self.request.sendall(MLLP_START + ack.encode() + MLLP_END)

        except Exception as exc:
            log.error("Error en handler MLLP: %s", exc)
        finally:
            conn.close()

    def _build_ack(self, msg: HL7v2Message) -> str:
        msg_control_id = msg.get("MSH", 10, 0)
        now = datetime.now().strftime("%Y%m%d%H%M%S")
        return (
            f"MSH|^~\\&|CARER_RECORD|HOSPITAL|{msg.get('MSH',3,0)}|{msg.get('MSH',4,0)}"
            f"|{now}||ACK|{msg_control_id}|P|2.5\r"
            f"MSA|AA|{msg_control_id}|Mensaje aceptado\r"
        )


def start_listener(port: int):
    log.info("Iniciando listener MLLP en puerto %d...", port)
    server = socketserver.ThreadingTCPServer(("0.0.0.0", port), MLLPHandler)
    server.allow_reuse_address = True
    log.info("Esperando mensajes HL7v2. Ctrl+C para detener.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Listener detenido.")
        server.shutdown()


# ── Generador de mensajes de prueba (desde CSV de Synthea) ───────────────────

def generate_test_messages(csv_path: str, host: str = "127.0.0.1", port: int = 2575):
    """
    Lee el CSV de pacientes de Synthea (output/csv/patients.csv)
    y envía mensajes ADT^A01 de prueba al listener MLLP.
    """
    log.info("Leyendo pacientes desde %s...", csv_path)

    with open(csv_path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        patients = list(reader)

    log.info("Generando %d mensajes ADT^A01 de prueba...", len(patients))

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((host, port))
    log.info("Conectado al listener en %s:%d", host, port)

    wards = ["UCI", "Pediatría", "Cirugía", "Medicina Interna", "Urgencias"]

    for i, p in enumerate(patients):
        # Synthea CSV: Id, BIRTHDATE, DEATHDATE, SSN, DRIVERS, PASSPORT,
        # PREFIX, FIRST, LAST, SUFFIX, MAIDEN, MARITAL, RACE, ETHNICITY,
        # GENDER, BIRTHPLACE, ADDRESS, CITY, STATE, COUNTY, FIPS, ZIP, LAT, LON,
        # HEALTHCARE_EXPENSES, HEALTHCARE_COVERAGE, INCOME
        patient_id = p.get("Id", str(uuid.uuid4()))[:20]
        first      = p.get("FIRST", "Desconocido")
        last       = p.get("LAST", "Desconocido")
        birth      = p.get("BIRTHDATE", "19700101").replace("-", "")[:8]
        gender     = "M" if p.get("GENDER", "").upper() == "M" else "F"
        ward       = wards[i % len(wards)]
        bed        = str((i % 10) + 1)
        now        = datetime.now().strftime("%Y%m%d%H%M%S")
        control_id = str(uuid.uuid4())[:20].replace("-", "")

        msg = (
            f"MSH|^~\\&|SYNTHEA|TEST_HOSPITAL|CARER_RECORD|PI|{now}||ADT^A01|{control_id}|P|2.5\r"
            f"EVN|A01|{now}\r"
            f"PID|1||{patient_id}^^^SYNTHEA||{last}^{first}||{birth}|{gender}||||\r"
            f"PV1|1|I|{ward}^101^{bed}||||||||||||||||V{i+1:04d}|||||||||||||||||||{now}\r"
        )

        sock.sendall(MLLP_START + msg.encode("utf-8") + MLLP_END)

        # Leer ACK
        ack = b""
        while MLLP_END not in ack:
            ack += sock.recv(1024)
        log.info("→ Enviado: %s %s | ACK recibido", first, last)

    sock.close()
    log.info("Generación de mensajes de prueba completada.")


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Adaptador HL7v2 MLLP")
    sub = parser.add_subparsers(dest="command", required=True)

    # Subcomando: listen
    p_listen = sub.add_parser("listen", help="Iniciar listener MLLP")
    p_listen.add_argument("--port", type=int, default=2575)

    # Subcomando: generate (pruebas)
    p_gen = sub.add_parser("generate", help="Enviar mensajes de prueba desde CSV de Synthea")
    p_gen.add_argument("--csv",  required=True, help="Ruta a patients.csv de Synthea")
    p_gen.add_argument("--host", default="127.0.0.1")
    p_gen.add_argument("--port", type=int, default=2575)

    args = parser.parse_args()

    if args.command == "listen":
        start_listener(args.port)
    elif args.command == "generate":
        generate_test_messages(args.csv, args.host, args.port)

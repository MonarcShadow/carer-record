#!/usr/bin/env python3
"""
Worker de transcripción de audio con faster-whisper.
Ejecutar como servicio systemd o manualmente:
    python3 -m app.workers.whisper_worker
"""
import time
import logging
from pathlib import Path
from sqlalchemy import create_engine, text
from faster_whisper import WhisperModel

# ── Config ────────────────────────────────────────────────────────────────────
from dotenv import load_dotenv
import os

load_dotenv(Path(__file__).parent.parent.parent / '.env')

DB_URL    = os.getenv('DATABASE_URL')
POLL_SECS = 5
MODEL_SIZE = "medium"
LOG_LEVEL  = logging.INFO

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [whisper_worker] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Cargar modelo una sola vez al iniciar ─────────────────────────────────────
log.info("Cargando modelo faster-whisper %s …", MODEL_SIZE)
model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
log.info("Modelo listo.")

engine = create_engine(DB_URL, pool_pre_ping=True)

def process_pending():
    with engine.connect() as conn:
        # Tomar un trabajo pendiente y marcarlo como 'processing'
        row = conn.execute(
            text("""
                SELECT id, audio_path
                FROM notes
                WHERE audio_status = 'pending'
                ORDER BY created_at ASC
                LIMIT 1
            """)
        ).fetchone()

        if not row:
            return

        note_id    = row.id
        audio_path = row.audio_path

        log.info("Procesando nota %s — archivo: %s", note_id, audio_path)

        # Marcar como 'processing'
        conn.execute(
            text("UPDATE notes SET audio_status = 'processing' WHERE id = :id"),
            {"id": note_id}
        )
        conn.commit()

    # Transcribir fuera del contexto de la conexión para no bloquear
    try:
        if not Path(audio_path).exists():
            raise FileNotFoundError(f"Audio no encontrado: {audio_path}")

        segments, info = model.transcribe(
            audio_path,
            language="es",          # español clínico
            beam_size=5,
            vad_filter=True,        # filtra silencios automáticamente
        )
        transcript = " ".join(s.text.strip() for s in segments).strip()

        log.info("Transcripción completada para %s: %d caracteres", note_id, len(transcript))

        with engine.connect() as conn:
            conn.execute(
                text("""
                    UPDATE notes
                    SET content      = :content,
                        audio_status = 'done'
                    WHERE id = :id
                """),
                {"content": transcript or "[sin contenido detectado]", "id": note_id}
            )
            conn.commit()

    except Exception as e:
        log.error("Error transcribiendo %s: %s", note_id, e)
        with engine.connect() as conn:
            conn.execute(
                text("UPDATE notes SET audio_status = 'error' WHERE id = :id"),
                {"id": note_id}
            )
            conn.commit()


if __name__ == "__main__":
    log.info("Worker iniciado. Revisando cola cada %ds …", POLL_SECS)
    while True:
        try:
            process_pending()
        except Exception as e:
            log.error("Error inesperado en el loop: %s", e)
        time.sleep(POLL_SECS)
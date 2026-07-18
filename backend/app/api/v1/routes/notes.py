from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db
from pydantic import BaseModel
from typing import Optional
from pathlib import Path
import uuid, os
from fastapi.responses import FileResponse


router = APIRouter()

AUDIO_DIR = Path("/home/pi/carer-record-audio")
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

class NoteCreate(BaseModel):
    patient_id:           str
    author_id:            str
    content:              str
    input_method:         Optional[str] = 'text'
    transcription_source: Optional[str] = 'manual'
    audio_confirmed:      Optional[bool] = True

@router.patch("/{note_id}/confirm")
def confirm_transcription(note_id: str, db: Session = Depends(get_db)):
    row = db.execute(
        text("SELECT id FROM notes WHERE id = :id"), {"id": note_id}
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Nota no encontrada")
    db.execute(
        text("UPDATE notes SET audio_confirmed = TRUE WHERE id = :id"),
        {"id": note_id}
    )
    db.commit()
    return {"ok": True}

@router.get("/audio/{note_id}")
def download_audio(note_id: str, db: Session = Depends(get_db)):
    row = db.execute(
        text("SELECT audio_path FROM notes WHERE id = :id"),
        {"id": note_id}
    ).fetchone()
    if not row or not row.audio_path:
        raise HTTPException(status_code=404, detail="Audio no encontrado")
    path = Path(row.audio_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Archivo de audio no encontrado")
    return FileResponse(
        path=str(path),
        media_type="audio/wav",
        filename=path.name,
    )

@router.get("/{patient_id}")
def list_notes(patient_id: str, db: Session = Depends(get_db)):
    result = db.execute(
        text("""
            SELECT
                n.id, n.content, n.input_method,
                n.transcription_source, n.audio_confirmed,
                n.audio_status,
                COALESCE(n.recorded_at, n.created_at) AS display_time,
                n.created_at, n.author_id,
                u.name AS author_name,
                u.role AS author_role
            FROM notes n
            JOIN users u ON n.author_id = u.id
            WHERE n.patient_id = :patient_id
            ORDER BY display_time ASC
        """),
        {"patient_id": patient_id}
    ).fetchall()
    return [dict(r._mapping) for r in result]


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_note(note: NoteCreate, db: Session = Depends(get_db)):
    _verify_patient_and_author(note.patient_id, note.author_id, db)
    note_id = str(uuid.uuid4())
    db.execute(
        text("""
            INSERT INTO notes
                (id, patient_id, author_id, content,
                 input_method, transcription_source, audio_confirmed)
            VALUES
                (:id, :patient_id, :author_id, :content,
                 :input_method, :transcription_source, :audio_confirmed)
        """),
        {
            "id":                   note_id,
            "patient_id":           note.patient_id,
            "author_id":            note.author_id,
            "content":              note.content,
            "input_method":         note.input_method,
            "transcription_source": note.transcription_source,
            "audio_confirmed":      note.audio_confirmed,
        }
    )
    db.commit()
    return _fetch_note(note_id, db)


@router.post("/audio", status_code=status.HTTP_201_CREATED)
async def create_note_from_audio(
    patient_id:  str = Form(...),
    author_id:   str = Form(...),
    recorded_at: str = Form(...),   # ISO 8601 desde el teléfono
    audio_file:  UploadFile = File(...),
    db: Session = Depends(get_db),
):
    _verify_patient_and_author(patient_id, author_id, db)

    # Guardar audio
    ext      = Path(audio_file.filename).suffix or '.wav'
    filename = f"{uuid.uuid4()}{ext}"
    filepath = AUDIO_DIR / filename
    with open(filepath, 'wb') as f:
        f.write(await audio_file.read())

    # Crear nota en estado pendiente
    note_id = str(uuid.uuid4())
    db.execute(
        text("""
            INSERT INTO notes
                (id, patient_id, author_id, recorded_at, content,
                 input_method, transcription_source, audio_confirmed,
                 audio_path, audio_status)
            VALUES
                (:id, :patient_id, :author_id, :recorded_at, '',
                 'voice', 'auto_whisper', FALSE,
                 :audio_path, 'pending')
        """),
        {
            "id":          note_id,
            "patient_id":  patient_id,
            "author_id":   author_id,
            "recorded_at": recorded_at,
            "audio_path":  str(filepath),
        }
    )
    db.commit()
    return _fetch_note(note_id, db)


# ── Helpers ────────────────────────────────────────────────────────────────────
def _verify_patient_and_author(patient_id: str, author_id: str, db: Session):
    if not db.execute(text("SELECT id FROM patients WHERE id = :id"),
                      {"id": patient_id}).fetchone():
        raise HTTPException(status_code=404, detail="Paciente no encontrado")
    if not db.execute(text("SELECT id FROM users WHERE id = :id"),
                      {"id": author_id}).fetchone():
        raise HTTPException(status_code=404, detail="Autor no encontrado")

def _fetch_note(note_id: str, db: Session):
    result = db.execute(
        text("""
            SELECT n.id, n.content, n.input_method,
                   n.transcription_source, n.audio_confirmed, n.audio_status,
                   COALESCE(n.recorded_at, n.created_at) AS display_time,
                   n.created_at, n.author_id,
                   u.name AS author_name, u.role AS author_role
            FROM notes n
            JOIN users u ON n.author_id = u.id
            WHERE n.id = :id
        """),
        {"id": note_id}
    ).fetchone()
    return dict(result._mapping)
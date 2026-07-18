from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db
from pydantic import BaseModel
from typing import Optional
import uuid

router = APIRouter()

class NoteCreate(BaseModel):
    patient_id:           str
    author_id:            str
    content:              str
    input_method:         Optional[str] = 'text'
    transcription_source: Optional[str] = 'manual'
    audio_confirmed:      Optional[bool] = True

@router.get("/{patient_id}")
def list_notes(patient_id: str, db: Session = Depends(get_db)):
    result = db.execute(
        text("""
            SELECT
                n.id, n.content, n.input_method,
                n.transcription_source, n.audio_confirmed,
                n.created_at, n.author_id,
                u.name  AS author_name,
                u.role  AS author_role
            FROM notes n
            JOIN users u ON n.author_id = u.id
            WHERE n.patient_id = :patient_id
            ORDER BY n.created_at ASC
        """),
        {"patient_id": patient_id}
    ).fetchall()
    return [dict(r._mapping) for r in result]

@router.post("/", status_code=status.HTTP_201_CREATED)
def create_note(note: NoteCreate, db: Session = Depends(get_db)):
    # Verificar que el paciente y el autor existen
    patient = db.execute(
        text("SELECT id FROM patients WHERE id = :id"),
        {"id": note.patient_id}
    ).fetchone()
    if not patient:
        raise HTTPException(status_code=404, detail="Paciente no encontrado")

    author = db.execute(
        text("SELECT id FROM users WHERE id = :id"),
        {"id": note.author_id}
    ).fetchone()
    if not author:
        raise HTTPException(status_code=404, detail="Autor no encontrado")

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

    result = db.execute(
        text("""
            SELECT n.id, n.content, n.input_method,
                   n.transcription_source, n.audio_confirmed,
                   n.created_at, n.author_id,
                   u.name AS author_name, u.role AS author_role
            FROM notes n
            JOIN users u ON n.author_id = u.id
            WHERE n.id = :id
        """),
        {"id": note_id}
    ).fetchone()
    return dict(result._mapping)
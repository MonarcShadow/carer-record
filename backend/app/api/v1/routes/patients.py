from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db

router = APIRouter()

@router.get("/")
def list_patients(db: Session = Depends(get_db)):
    result = db.execute(
        text("""
            SELECT
                id, first_name, last_name, birth_date, gender,
                ward, bed_number, admission_date, primary_diagnosis
            FROM patients
            WHERE active = TRUE AND deceased = FALSE
            ORDER BY last_name ASC, first_name ASC
        """)
    ).fetchall()
    return [dict(r._mapping) for r in result]


@router.get("/{patient_id}")
def get_patient(patient_id: str, db: Session = Depends(get_db)):
    result = db.execute(
        text("""
            SELECT
                id, first_name, last_name, birth_date, gender,
                phone, address, marital_status, language, ethnicity,
                ward, bed_number, admission_date, expected_discharge_date,
                primary_diagnosis, source_system, created_at
            FROM patients
            WHERE id = :id
        """),
        {"id": patient_id}
    ).fetchone()
    if not result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Paciente no encontrado"
        )
    return dict(result._mapping)
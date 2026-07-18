from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db

router = APIRouter()

@router.get("/")
def list_patients(db: Session = Depends(get_db)):
    result = db.execute(
        text("""
            SELECT id, first_name, last_name, birth_date, gender,
                   ward, bed_number, admission_date, primary_diagnosis
            FROM patients
            WHERE active = TRUE AND deceased = FALSE
            ORDER BY last_name ASC, first_name ASC
        """)
    ).fetchall()
    return [dict(r._mapping) for r in result]


@router.get("/{patient_id}")
def get_patient(patient_id: str, db: Session = Depends(get_db)):
    patient = db.execute(
        text("""
            SELECT id, first_name, last_name, birth_date, gender,
                   phone, address, marital_status, language, ethnicity,
                   ward, bed_number, admission_date, expected_discharge_date,
                   primary_diagnosis, source_system, created_at
            FROM patients WHERE id = :id
        """),
        {"id": patient_id}
    ).fetchone()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Paciente no encontrado")

    encounters = db.execute(
        text("""
            SELECT encounter_type, status, start_date, end_date,
                   reason, practitioner_name, referral_reason, encounter_class
            FROM encounters
            WHERE patient_id = :id
            ORDER BY start_date DESC
        """),
        {"id": patient_id}
    ).fetchall()

    conditions = db.execute(
        text("""
            SELECT description, status, severity,
                   onset_date, abatement_date, recorded_by
            FROM conditions
            WHERE patient_id = :id
            ORDER BY onset_date DESC
        """),
        {"id": patient_id}
    ).fetchall()

    medications = db.execute(
        text("""
            SELECT description, dosage, frequency, prescriber,
                   instructions, status, start_date, end_date
            FROM medications
            WHERE patient_id = :id
            ORDER BY start_date DESC
        """),
        {"id": patient_id}
    ).fetchall()

    observations = db.execute(
        text("""
            SELECT description, value, unit, value_high, value_low,
                   interpretation, category, status, effective_date
            FROM observations
            WHERE patient_id = :id
            ORDER BY effective_date DESC
        """),
        {"id": patient_id}
    ).fetchall()

    allergies = db.execute(
        text("""
            SELECT description, severity, status,
                   onset_date, reaction, last_occurrence, recorded_by
            FROM allergies
            WHERE patient_id = :id
            ORDER BY onset_date DESC
        """),
        {"id": patient_id}
    ).fetchall()

    return {
        **dict(patient._mapping),
        "encounters":   [dict(r._mapping) for r in encounters],
        "conditions":   [dict(r._mapping) for r in conditions],
        "medications":  [dict(r._mapping) for r in medications],
        "observations": [dict(r._mapping) for r in observations],
        "allergies":    [dict(r._mapping) for r in allergies],
    }
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

    def q(sql, params=None):
        return [dict(r._mapping) for r in
                db.execute(text(sql), params or {"id": patient_id}).fetchall()]

    return {
        **dict(patient._mapping),
        "sections": {
            "encounters": q("""
                SELECT encounter_type, status, encounter_class,
                       start_date, end_date, reason,
                       practitioner_name, referral_reason
                FROM encounters WHERE patient_id = :id
                ORDER BY start_date DESC"""),

            "conditions": q("""
                SELECT description, status, severity,
                       onset_date, abatement_date, recorded_by
                FROM conditions WHERE patient_id = :id
                ORDER BY onset_date DESC"""),

            "medications": q("""
                SELECT description, status, dosage, frequency,
                       prescriber, instructions, start_date, end_date
                FROM medications WHERE patient_id = :id
                ORDER BY start_date DESC"""),

            "observations": q("""
                SELECT description, category, value, unit,
                       value_low, value_high, interpretation,
                       status, effective_date
                FROM observations WHERE patient_id = :id
                ORDER BY effective_date DESC"""),

            "allergies": q("""
                SELECT description, severity, status,
                       onset_date, reaction,
                       last_occurrence, recorded_by
                FROM allergies WHERE patient_id = :id
                ORDER BY onset_date DESC"""),

            "procedures": q("""
                SELECT description, status, performed_date,
                       performer, reason, body_site
                FROM procedures WHERE patient_id = :id
                ORDER BY performed_date DESC"""),

            "immunizations": q("""
                SELECT description, status, occurrence_date,
                       lot_number, manufacturer, site,
                       route, performer
                FROM immunizations WHERE patient_id = :id
                ORDER BY occurrence_date DESC"""),

            "diagnostic_reports": q("""
                SELECT description, category, status,
                       effective_date, issued_date,
                       performer, conclusion
                FROM diagnostic_reports WHERE patient_id = :id
                ORDER BY effective_date DESC"""),

            "imaging_studies": q("""
                SELECT description, modality, status,
                       started_date, body_site,
                       number_series, number_instances, referrer
                FROM imaging_studies WHERE patient_id = :id
                ORDER BY started_date DESC"""),

            "devices": q("""
                SELECT description, status, manufacturer,
                       model, lot_number, serial_number,
                       expiration_date, udi
                FROM devices WHERE patient_id = :id"""),

            "care_plans": q("""
                SELECT title, description, status, intent,
                       category, start_date, end_date
                FROM care_plans WHERE patient_id = :id
                ORDER BY start_date DESC"""),

            "care_team": q("""
                SELECT ctm.member_name, ctm.role, ctm.member_type,
                       ct.name, ct.status, ct.category
                FROM care_team_members ctm
                JOIN care_teams ct ON ctm.care_team_id = ct.id
                WHERE ctm.patient_id = :id"""),
        }
    }
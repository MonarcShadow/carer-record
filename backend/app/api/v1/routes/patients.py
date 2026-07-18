from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db

router = APIRouter()

@router.get("/")
def list_patients(db: Session = Depends(get_db)):
    result = db.execute(
        text("""
            SELECT
                id,
                first_name,
                last_name,
                birth_date,
                gender,
                ward,
                bed_number,
                admission_date,
                primary_diagnosis
            FROM patients
            WHERE active = TRUE AND deceased = FALSE
            ORDER BY last_name ASC, first_name ASC
        """)
    ).fetchall()
    return [dict(r._mapping) for r in result]
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db
from app.core.security import hash_password
from pydantic import BaseModel
from typing import Optional
import uuid

router = APIRouter()

class UserResponse(BaseModel):
    id: str
    name: str
    email: str
    rut: str
    role: str
    active: bool

class UserCreate(BaseModel):
    name: str
    email: str
    rut: str
    role: str
    password: str

class UserUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
    rut: Optional[str] = None
    role: Optional[str] = None
    password: Optional[str] = None
    active: Optional[bool] = None

@router.get("/", response_model=list[UserResponse])
def list_users(db: Session = Depends(get_db)):
    result = db.execute(
        text("SELECT id, name, email, rut, role, active FROM users ORDER BY name ASC")
    ).fetchall()
    return [dict(r._mapping) for r in result]

@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    # Verificar duplicados
    existing = db.execute(
        text("SELECT id FROM users WHERE email = :email OR rut = :rut"),
        {"email": user.email, "rut": user.rut}
    ).fetchone()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya existe un usuario con ese correo o RUT"
        )

    user_id = str(uuid.uuid4())
    db.execute(
        text("""
            INSERT INTO users (id, name, email, rut, role, password_hash, active)
            VALUES (:id, :name, :email, :rut, :role, :password_hash, TRUE)
        """),
        {
            "id":            user_id,
            "name":          user.name,
            "email":         user.email,
            "rut":           user.rut,
            "role":          user.role,
            "password_hash": hash_password(user.password),
        }
    )
    db.commit()

    result = db.execute(
        text("SELECT id, name, email, rut, role, active FROM users WHERE id = :id"),
        {"id": user_id}
    ).fetchone()
    return dict(result._mapping)

@router.put("/{user_id}", response_model=UserResponse)
def update_user(user_id: str, user: UserUpdate, db: Session = Depends(get_db)):
    existing = db.execute(
        text("SELECT id FROM users WHERE id = :id"),
        {"id": user_id}
    ).fetchone()
    if not existing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")

    fields = []
    params = {"id": user_id}

    if user.name     is not None: fields.append("name = :name");           params["name"]          = user.name
    if user.email    is not None: fields.append("email = :email");          params["email"]         = user.email
    if user.rut      is not None: fields.append("rut = :rut");              params["rut"]           = user.rut
    if user.role     is not None: fields.append("role = :role");            params["role"]          = user.role
    if user.active   is not None: fields.append("active = :active");        params["active"]        = user.active
    if user.password is not None: fields.append("password_hash = :phash");  params["phash"]         = hash_password(user.password)

    if fields:
        db.execute(text(f"UPDATE users SET {', '.join(fields)} WHERE id = :id"), params)
        db.commit()

    result = db.execute(
        text("SELECT id, name, email, rut, role, active FROM users WHERE id = :id"),
        {"id": user_id}
    ).fetchone()
    return dict(result._mapping)

@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(user_id: str, db: Session = Depends(get_db)):
    existing = db.execute(
        text("SELECT id FROM users WHERE id = :id"),
        {"id": user_id}
    ).fetchone()
    if not existing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")
    db.execute(text("DELETE FROM users WHERE id = :id"), {"id": user_id})
    db.commit()
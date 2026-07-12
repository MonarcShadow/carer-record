from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db
from app.core.security import verify_password, create_access_token
from app.schemas.auth import LoginRequest, TokenResponse

router = APIRouter()

@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    result = db.execute(
        text("SELECT id, name, role, password_hash, active FROM users WHERE email = :email"),
        {"email": request.email}
    ).fetchone()

    if not result:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos"
        )

    if not result.active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Usuario inactivo"
        )

    if not verify_password(request.password, result.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos"
        )

    token = create_access_token({
        "sub": result.id,
        "role": result.role,
        "name": result.name
    })

    return TokenResponse(
        access_token=token,
        user_name=result.name,
        user_role=result.role
    )
from fastapi import FastAPI
from app.core.config import settings
from app.core.database import engine
from sqlalchemy import text

app = FastAPI(
    title="Carer Record API",
    version="0.1.0",
    docs_url="/docs",
)

@app.get("/")
def root():
    return {"status": "ok", "environment": settings.ENVIRONMENT}

@app.get("/health")
def health():
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ok", "database": "connected"}
    except Exception as e:
        return {"status": "error", "database": str(e)}

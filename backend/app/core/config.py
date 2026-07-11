from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str = "mysql+pymysql://admin:admin@localhost/carer_record"
    SECRET_KEY: str = "dev-secret-key-change-in-production"
    ENVIRONMENT: str = "development"
    API_V1_PREFIX: str = "/api/v1"

    class Config:
        env_file = ".env"

settings = Settings()

from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # App
    APP_NAME: str = "Attendance Tracking System"
    DEBUG: bool = False
    API_V1_STR: str = "/api/v1"

    # Database
    DATABASE_URL: str = "postgresql://postgres:postgres@db:5432/attendance_db"

    # JWT
    SECRET_KEY: str = "your-super-secret-key-change-in-production-!!!"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Work schedule
    WORK_START_HOUR: int = 9
    WORK_START_MINUTE: int = 0
    WORK_END_HOUR: int = 18
    WORK_END_MINUTE: int = 0
    GRACE_PERIOD_MINUTES: int = 10

    # CORS
    BACKEND_CORS_ORIGINS: list = ["*"]

    class Config:
        env_file = ".env"
        case_sensitive = True

    
    APP_NAME: str = "Attendance Tracking System"
    DEBUG: bool = False
    API_V1_STR: str = "/api/v1"
    AUTO_CREATE_TABLES: bool = True


settings = Settings()
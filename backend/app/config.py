from pydantic import ConfigDict
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # App
    APP_NAME: str = "SoftTime"
    DEBUG: bool = False
    API_V1_STR: str = "/api/v1"

    # Database — psycopg2 (sync). asyncpg reserved for future async migration.
    DATABASE_URL: str = "postgresql+psycopg2://softtime:softtime123@db:5432/softtime_db"

    # Redis
    REDIS_URL: str = "redis://redis:6379"

    # JWT
    SECRET_KEY: str = "change-me-to-a-random-32-char-string!!"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Work schedule defaults
    WORK_START_HOUR: int = 9
    WORK_START_MINUTE: int = 0
    WORK_END_HOUR: int = 18
    WORK_END_MINUTE: int = 0
    GRACE_PERIOD_MINUTES: int = 5

    # CORS — admin_web использует same-origin, мобильное приложение CORS не использует
    BACKEND_CORS_ORIGINS: list = ["*"]

    # Ключ для публичных эндпоинтов регистрации (Flutter app)
    APP_REGISTRATION_KEY: str = "change-me-registration-key"

    # Auto-create tables on startup — отключено, используется Alembic
    AUTO_CREATE_TABLES: bool = False

    # Database variables for Docker compatibility
    POSTGRES_DB: str = "softtime_db"
    POSTGRES_USER: str = "softtime"
    POSTGRES_PASSWORD: str = "softtime123"

    # Firebase legacy (not used by admin sdk but present in .env)
    FCM_SERVER_KEY: str = ""

    # Admin defaults
    DEFAULT_ADMIN_USERNAME: str = "admin"
    DEFAULT_ADMIN_EMAIL: str = "admin@softjol.com"
    DEFAULT_ADMIN_PASSWORD: str = "admin123"
    DEFAULT_ADMIN_PHONE: str = "+99600000000"

    model_config = ConfigDict(env_file=".env", case_sensitive=True, extra="ignore")


settings = Settings()

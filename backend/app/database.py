from sqlalchemy import create_engine, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def ensure_users_team_schema(engine) -> None:
    """Align DB with User.team_id when tables were created via create_all (no ALTER)."""
    dialect = engine.dialect.name
    if dialect != "postgresql":
        return
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS teams (
                    id UUID PRIMARY KEY NOT NULL,
                    name VARCHAR(100) NOT NULL,
                    description TEXT,
                    mentor_id UUID REFERENCES users(id),
                    created_at TIMESTAMPTZ DEFAULT now(),
                    updated_at TIMESTAMPTZ DEFAULT now(),
                    CONSTRAINT uq_teams_name UNIQUE (name)
                );
                """
            )
        )
        conn.execute(
            text("ALTER TABLE users ADD COLUMN IF NOT EXISTS team_id UUID")
        )
        conn.execute(
            text(
                """
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_team_id'
                    ) THEN
                        ALTER TABLE users
                        ADD CONSTRAINT fk_users_team_id
                        FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL;
                    END IF;
                END $$;
                """
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_users_team_id ON users (team_id)"
            )
        )


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

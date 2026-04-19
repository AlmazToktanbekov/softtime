import os
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.database import engine, Base
from app import models  # noqa — ensure all models are imported for create_all
from app.routers import auth, attendance, reports
from app.routers.users import router as users_router
from app.routers.teams import router as teams_router
from app.routers.office_networks import networks_router, qr_router
from app.routers.settings import router as settings_router
from app.routers.absence_requests import router as absence_requests_router
from app.routers.duty import router as duty_router
from app.routers.news import router as news_router
from app.routers.tasks import router as tasks_router
from app.routers.employee_schedules import router as employee_schedules_router
from app.routers.audit_logs import router as audit_logs_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup ────────────────────────────────────────────────────────────────
    if settings.AUTO_CREATE_TABLES:
        Base.metadata.create_all(bind=engine)

    from app.database import ensure_users_team_schema
    ensure_users_team_schema(engine)

    from app.database import SessionLocal
    from app.bootstrap import ensure_default_data
    db = SessionLocal()
    try:
        ensure_default_data(db)
    finally:
        db.close()

    from app.services.cron_service import setup_scheduler
    scheduler = setup_scheduler()
    scheduler.start()
    app.state.scheduler = scheduler

    yield

    # ── Shutdown ───────────────────────────────────────────────────────────────
    scheduler = getattr(app.state, "scheduler", None)
    if scheduler and scheduler.running:
        scheduler.shutdown(wait=False)


app = FastAPI(
    title=settings.APP_NAME,
    description="SoftTime — система управления офисом и командой",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

prefix = settings.API_V1_STR
app.include_router(auth.router, prefix=prefix)
app.include_router(users_router, prefix=prefix)
app.include_router(teams_router, prefix=prefix)
app.include_router(attendance.router, prefix=prefix)
app.include_router(networks_router, prefix=prefix)
app.include_router(qr_router, prefix=prefix)
app.include_router(reports.router, prefix=prefix)
app.include_router(absence_requests_router, prefix=prefix)
app.include_router(duty_router, prefix=prefix)
app.include_router(news_router, prefix=prefix)
app.include_router(tasks_router, prefix=prefix)
app.include_router(employee_schedules_router, prefix=prefix)
app.include_router(audit_logs_router, prefix=prefix)
app.include_router(settings_router, prefix=prefix)

# Serve uploaded files (avatars, etc.)
_uploads_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
os.makedirs(_uploads_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=_uploads_dir), name="uploads")


def _resolve_admin_web_dir() -> Optional[str]:
    """Папка admin_web: .env ADMIN_WEB_DIR или рядом с backend в репозитории / в образе."""
    explicit = os.getenv("ADMIN_WEB_DIR", "").strip()
    if explicit:
        p = os.path.abspath(explicit)
        return p if os.path.isfile(os.path.join(p, "index.html")) else None
    here = os.path.dirname(os.path.abspath(__file__))
    backend_root = os.path.dirname(here)
    project_root = os.path.dirname(backend_root)
    for candidate in (
        os.path.join(project_root, "admin_web"),
        os.path.join(backend_root, "admin_web"),
    ):
        if os.path.isfile(os.path.join(candidate, "index.html")):
            return candidate
    return None


_admin_static = _resolve_admin_web_dir()
if _admin_static:
    app.mount(
        "/admin",
        StaticFiles(directory=_admin_static, html=True),
        name="admin_web",
    )


@app.get("/")
def root():
    return {
        "name": settings.APP_NAME,
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs",
        "admin_web": "/admin/" if _admin_static else None,
    }


@app.get("/health")
def health():
    return {"status": "healthy"}

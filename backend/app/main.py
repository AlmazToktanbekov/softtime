from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import engine, Base
from app import models  # noqa - ensure all models are imported
from app.routers import auth, employees, attendance, reports
from app.routers.office_networks import networks_router, qr_router
from app.routers.settings import router as settings_router
from app.routers.absence_requests import router as absence_requests_router

app = FastAPI(
    title=settings.APP_NAME,
    description="Система учета посещаемости сотрудников — REST API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
prefix = settings.API_V1_STR
app.include_router(settings_router, prefix=prefix)
app.include_router(auth.router, prefix=prefix)
app.include_router(employees.router, prefix=prefix)
app.include_router(attendance.router, prefix=prefix)
app.include_router(networks_router, prefix=prefix)
app.include_router(qr_router, prefix=prefix)
app.include_router(reports.router, prefix=prefix)
app.include_router(absence_requests_router, prefix=prefix)


@app.on_event("startup")
def on_startup():
    if settings.AUTO_CREATE_TABLES:
        Base.metadata.create_all(bind=engine)


@app.get("/")
def root():
    return {
        "name": settings.APP_NAME,
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs"
    }


@app.get("/health")
def health():
    return {"status": "healthy"}

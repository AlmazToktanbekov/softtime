from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.work_settings import WorkSettings
from app.schemas.work_settings import WorkSettingsResponse, WorkSettingsUpdate
from app.utils.dependencies import require_admin

router = APIRouter(prefix="/settings", tags=["Настройки"])


def get_or_create_settings(db: Session) -> WorkSettings:
    settings = db.query(WorkSettings).first()
    if not settings:
        settings = WorkSettings(
            work_start_hour=9,
            work_start_minute=0,
            work_end_hour=18,
            work_end_minute=0,
            grace_period_minutes=10,
            count_early_arrival=True,
            count_early_leave=True,
            count_overtime=True,
        )
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings


@router.get("/work-time", response_model=WorkSettingsResponse)
def get_work_time_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    return get_or_create_settings(db)


@router.put("/work-time", response_model=WorkSettingsResponse)
def update_work_time_settings(
    data: WorkSettingsUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    settings = get_or_create_settings(db)

    settings.work_start_hour = data.work_start_hour
    settings.work_start_minute = data.work_start_minute
    settings.work_end_hour = data.work_end_hour
    settings.work_end_minute = data.work_end_minute
    settings.grace_period_minutes = data.grace_period_minutes
    settings.count_early_arrival = data.count_early_arrival
    settings.count_early_leave = data.count_early_leave
    settings.count_overtime = data.count_overtime

    db.commit()
    db.refresh(settings)
    return settings
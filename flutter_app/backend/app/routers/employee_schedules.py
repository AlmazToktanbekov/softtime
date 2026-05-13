from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.employee_schedule import EmployeeSchedule
from app.schemas.employee_schedule import (
    EmployeeScheduleCreate,
    EmployeeScheduleUpdate,
    EmployeeScheduleResponse,
)
from app.utils.dependencies import get_current_user

router = APIRouter(prefix="/employee-schedules", tags=["Расписание"])

MIN_WORK_HOURS = 6


def _validate_work_duration(is_working_day, start_time, end_time):
    """Рабочий день должен быть не менее 6 часов (ТЗ §2.2)."""
    if not is_working_day:
        return
    if start_time is None or end_time is None:
        return
    from datetime import datetime, date
    start_dt = datetime.combine(date.today(), start_time)
    end_dt = datetime.combine(date.today(), end_time)
    duration_hours = (end_dt - start_dt).total_seconds() / 3600
    if duration_hours < MIN_WORK_HOURS:
        raise HTTPException(
            status_code=400,
            detail=f"Минимальная продолжительность рабочего дня — {MIN_WORK_HOURS} часов. "
                   f"Указано: {duration_hours:.1f} ч."
        )


def _check_schedule_access(
    target_user_id: UUID,
    current_user: User,
    db: Session,
) -> User:
    target = db.query(User).filter(User.id == target_user_id, User.deleted_at.is_(None)).first()
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    if current_user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        return target
    if current_user.role == UserRole.TEAM_LEAD:
        if target_user_id == current_user.id:
            return target
        mentee = (
            db.query(User)
            .filter(User.id == target_user_id, User.mentor_id == current_user.id)
            .first()
        )
        if mentee:
            return target
        raise HTTPException(status_code=403, detail="Доступ запрещён")
    if current_user.id == target_user_id:
        return target
    raise HTTPException(status_code=403, detail="Доступ запрещён")


def _schedules_for_user(
    user_id: UUID,
    db: Session,
    current_user: User,
) -> List[EmployeeSchedule]:
    _check_schedule_access(user_id, current_user, db)
    return (
        db.query(EmployeeSchedule)
        .filter(EmployeeSchedule.user_id == user_id)
        .order_by(EmployeeSchedule.day_of_week)
        .all()
    )


@router.get("/user/{user_id}", response_model=List[EmployeeScheduleResponse])
def get_schedules_by_user(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _schedules_for_user(user_id, db, current_user)


@router.get("/employee/{user_id}", response_model=List[EmployeeScheduleResponse])
def get_schedules_by_user_legacy(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Совместимость с клиентом Flutter (/employee/{id})."""
    return _schedules_for_user(user_id, db, current_user)


@router.post("/user/{user_id}", response_model=EmployeeScheduleResponse)
def create_or_update_schedule(
    user_id: UUID,
    data: EmployeeScheduleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Создать или обновить день расписания (админ / тимлид / сам пользователь — только чтение для employee? TZ: админ/тимлид)."""
    if current_user.role not in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    ):
        raise HTTPException(status_code=403, detail="Редактирование расписания только у администратора или тимлида")

    target = _check_schedule_access(user_id, current_user, db)

    _validate_work_duration(data.is_working_day, data.start_time, data.end_time)

    existing = (
        db.query(EmployeeSchedule)
        .filter(
            EmployeeSchedule.user_id == target.id,
            EmployeeSchedule.day_of_week == data.day_of_week,
        )
        .first()
    )

    if existing:
        existing.is_working_day = data.is_working_day
        existing.start_time = data.start_time
        existing.end_time = data.end_time
        db.commit()
        db.refresh(existing)
        return existing

    row = EmployeeSchedule(
        user_id=target.id,
        day_of_week=data.day_of_week,
        is_working_day=data.is_working_day,
        start_time=data.start_time,
        end_time=data.end_time,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.post("/employee/{user_id}", response_model=EmployeeScheduleResponse)
def create_or_update_schedule_legacy(
    user_id: UUID,
    data: EmployeeScheduleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Совместимость с Flutter: POST /employee-schedules/employee/{id}."""
    return create_or_update_schedule(user_id, data, db, current_user)


@router.patch("/{schedule_id}", response_model=EmployeeScheduleResponse)
def update_schedule(
    schedule_id: UUID,
    data: EmployeeScheduleUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    ):
        raise HTTPException(status_code=403, detail="Нет прав")

    sched = db.query(EmployeeSchedule).filter(EmployeeSchedule.id == schedule_id).first()
    if not sched:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    _check_schedule_access(sched.user_id, current_user, db)

    if data.day_of_week is not None:
        if not 0 <= data.day_of_week <= 6:
            raise HTTPException(status_code=400, detail="day_of_week 0–6")
        if data.day_of_week != sched.day_of_week:
            clash = (
                db.query(EmployeeSchedule)
                .filter(
                    EmployeeSchedule.user_id == sched.user_id,
                    EmployeeSchedule.day_of_week == data.day_of_week,
                )
                .first()
            )
            if clash:
                raise HTTPException(status_code=400, detail="На этот день уже есть расписание")
        sched.day_of_week = data.day_of_week
    if data.is_working_day is not None:
        sched.is_working_day = data.is_working_day
    if data.start_time is not None:
        sched.start_time = data.start_time
    if data.end_time is not None:
        sched.end_time = data.end_time

    # Проверяем итоговые значения после применения изменений
    _validate_work_duration(sched.is_working_day, sched.start_time, sched.end_time)

    db.commit()
    db.refresh(sched)
    return sched


@router.delete("/{schedule_id}")
def delete_schedule(
    schedule_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    ):
        raise HTTPException(status_code=403, detail="Нет прав")

    sched = db.query(EmployeeSchedule).filter(EmployeeSchedule.id == schedule_id).first()
    if not sched:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    _check_schedule_access(sched.user_id, current_user, db)

    db.delete(sched)
    db.commit()
    return {"message": "Удалено"}

from datetime import timedelta, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    AbsenceRequest,
    AbsenceRequestStatus,
    AbsenceRequestType,
    Attendance,
    AttendanceStatus,
    Employee,
    User,
)
from app.schemas.absence_request import (
    AbsenceRequestCreate,
    AbsenceRequestResponse,
    AbsenceRequestReview,
)
from app.utils.dependencies import get_current_user, require_admin

router = APIRouter(prefix="/absence-requests", tags=["Заявки"])


def _iter_dates(start, end):
    cur = start
    while cur <= end:
        yield cur
        cur += timedelta(days=1)


def _apply_request_to_attendance(
    db: Session,
    req: AbsenceRequest,
    reviewer: User,
) -> None:
    """
    При одобрении заявки обновить/создать записи посещаемости согласно ТЗ:
    - sick            -> sick_leave
    - vacation        -> vacation
    - remote_work     -> remote_work
    - business_trip   -> business_trip
    - family/other    -> approved_absence
    - late_reason     -> approved_late_arrival (на дату start_date)
    - early_leave     -> approved_early_leave (на дату start_date)
    """
    emp = db.query(Employee).filter(
        Employee.id == req.employee_id,
        Employee.is_active == True,
    ).first()
    if not emp:
        raise HTTPException(status_code=400, detail="Сотрудник не найден или неактивен")

    def map_status(rt: AbsenceRequestType, *, for_single_day: bool) -> AttendanceStatus:
        if rt == AbsenceRequestType.sick:
            return AttendanceStatus.manual  # в расширенном enum может быть sick_leave
        if rt == AbsenceRequestType.vacation:
            return AttendanceStatus.manual
        if rt == AbsenceRequestType.remote_work:
            return AttendanceStatus.manual
        if rt == AbsenceRequestType.business_trip:
            return AttendanceStatus.manual
        if rt in (AbsenceRequestType.family, AbsenceRequestType.other):
            return AttendanceStatus.approved_absence
        if rt == AbsenceRequestType.late_reason and for_single_day:
            return AttendanceStatus.manual
        if rt == AbsenceRequestType.early_leave and for_single_day:
            return AttendanceStatus.manual
        return AttendanceStatus.manual

    # Много-дневные заявки по типу “отсутствие”
    if req.request_type in {
        AbsenceRequestType.sick,
        AbsenceRequestType.family,
        AbsenceRequestType.vacation,
        AbsenceRequestType.business_trip,
        AbsenceRequestType.remote_work,
        AbsenceRequestType.other,
    }:
        end_date = req.end_date or req.start_date
        for d in _iter_dates(req.start_date, end_date):
            record = (
                db.query(Attendance)
                .filter(Attendance.employee_id == req.employee_id, Attendance.date == d)
                .first()
            )
            status = map_status(req.request_type, for_single_day=False)
            if record:
                record.status = status
                record.note = req.comment_admin or req.comment_employee
            else:
                record = Attendance(
                    employee_id=req.employee_id,
                    date=d,
                    status=status,
                    note=req.comment_admin or req.comment_employee,
                )
                db.add(record)

    # Точечные заявки по времени (опоздание / ранний уход)
    if req.request_type in {AbsenceRequestType.late_reason, AbsenceRequestType.early_leave}:
        d = req.start_date
        record = (
            db.query(Attendance)
            .filter(Attendance.employee_id == req.employee_id, Attendance.date == d)
            .first()
        )
        if not record:
            # создаём минимальную запись, чтобы пометить день как одобренный
            record = Attendance(
                employee_id=req.employee_id,
                date=d,
                status=map_status(req.request_type, for_single_day=True),
                note=req.comment_admin or req.comment_employee,
            )
            db.add(record)
        else:
            record.status = map_status(req.request_type, for_single_day=True)
            note = req.comment_admin or req.comment_employee
            if note:
                record.note = note


@router.post("", response_model=AbsenceRequestResponse)
def create_absence_request(
    data: AbsenceRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Создать заявку (только за себя)."""
    if not current_user.employee_id:
        raise HTTPException(status_code=400, detail="Профиль сотрудника не найден")

    req = AbsenceRequest(
        employee_id=current_user.employee_id,
        request_type=data.request_type,
        start_date=data.start_date,
        end_date=data.end_date,
        start_time=data.start_time,
        comment_employee=data.comment_employee,
        status=AbsenceRequestStatus.new,
    )
    db.add(req)
    db.commit()
    db.refresh(req)
    return req


@router.get("/my", response_model=List[AbsenceRequestResponse])
def list_my_absence_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Список собственных заявок."""
    if not current_user.employee_id:
        return []
    q = (
        db.query(AbsenceRequest)
        .filter(AbsenceRequest.employee_id == current_user.employee_id)
        .order_by(AbsenceRequest.created_at.desc())
    )
    return q.all()


@router.get("", response_model=List[AbsenceRequestResponse])
def list_absence_requests(
    status: Optional[AbsenceRequestStatus] = Query(default=None),
    employee_id: Optional[int] = Query(default=None),
    request_type: Optional[AbsenceRequestType] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Список всех заявок (для администратора) с фильтрами."""
    q = db.query(AbsenceRequest)
    if status is not None:
        q = q.filter(AbsenceRequest.status == status)
    if employee_id is not None:
        q = q.filter(AbsenceRequest.employee_id == employee_id)
    if request_type is not None:
        q = q.filter(AbsenceRequest.request_type == request_type)

    return q.order_by(AbsenceRequest.created_at.desc()).all()


@router.get("/{request_id}", response_model=AbsenceRequestResponse)
def get_absence_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    req = db.query(AbsenceRequest).filter(AbsenceRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Заявка не найдена")
    return req


@router.patch("/{request_id}/review", response_model=AbsenceRequestResponse)
def review_absence_request(
    request_id: int,
    data: AbsenceRequestReview,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Рассмотрение заявки администратором."""
    req = db.query(AbsenceRequest).filter(AbsenceRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Заявка не найдена")

    # Обновляем статус и комментарий администратора
    req.status = data.status
    req.comment_admin = data.comment_admin
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.utcnow()

    # При одобрении применяем к посещаемости
    if data.status == AbsenceRequestStatus.approved:
        _apply_request_to_attendance(db, req, current_user)

    db.commit()
    db.refresh(req)
    return req


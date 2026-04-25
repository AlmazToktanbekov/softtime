from datetime import timedelta, datetime, timezone
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.models import (
    AbsenceRequest,
    AbsenceRequestStatus,
    AbsenceRequestType,
    Attendance,
    AttendanceStatus,
    User,
    UserRole,
    UserStatus,
)
from app.schemas.absence_request import (
    AbsenceRequestCreate,
    AbsenceRequestResponse,
    AbsenceRequestReview,
)
from app.utils.dependencies import get_current_user, require_admin
from app.utils.fcm import notify_user, notify_users

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
    uid = req.user_id

    def map_status(rt: AbsenceRequestType, *, for_single_day: bool) -> AttendanceStatus:
        # Все типы отсутствия с одобрением администратора → APPROVED_ABSENCE
        if rt in (
            AbsenceRequestType.sick,
            AbsenceRequestType.vacation,
            AbsenceRequestType.remote_work,
            AbsenceRequestType.business_trip,
            AbsenceRequestType.family,
            AbsenceRequestType.other,
        ):
            return AttendanceStatus.APPROVED_ABSENCE
        # Опоздание/ранний уход с причиной — не меняем статус дня, только добавляем примечание
        if rt in (AbsenceRequestType.late_reason, AbsenceRequestType.early_leave) and for_single_day:
            return AttendanceStatus.APPROVED_ABSENCE
        return AttendanceStatus.APPROVED_ABSENCE

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
                .filter(Attendance.user_id == uid, Attendance.date == d)
                .first()
            )
            status = map_status(req.request_type, for_single_day=False)
            if record:
                record.status = status
                record.note = req.comment_admin or req.comment_employee
            else:
                record = Attendance(
                    user_id=uid,
                    date=d,
                    status=status,
                    note=req.comment_admin or req.comment_employee,
                )
                db.add(record)

    if req.request_type in {AbsenceRequestType.late_reason, AbsenceRequestType.early_leave}:
        d = req.start_date
        record = (
            db.query(Attendance)
            .filter(Attendance.user_id == uid, Attendance.date == d)
            .first()
        )
        if not record:
            record = Attendance(
                user_id=uid,
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
    if data.end_date and data.end_date < data.start_date:
        raise HTTPException(status_code=400, detail="Дата окончания не может быть раньше даты начала")

    req = AbsenceRequest(
        user_id=current_user.id,
        request_type=data.request_type,
        start_date=data.start_date,
        end_date=data.end_date,
        start_time=data.start_time,
        comment_employee=data.comment_employee,
        status=AbsenceRequestStatus.new,
    )
    db.add(req)
    db.commit()
    req = (
        db.query(AbsenceRequest)
        .options(joinedload(AbsenceRequest.user))
        .filter(AbsenceRequest.id == req.id)
        .first()
    )

    # Push notification → Admin и Super Admin
    admins = (
        db.query(User)
        .filter(
            User.deleted_at.is_(None),
            User.status == UserStatus.ACTIVE,
            User.role.in_((UserRole.ADMIN, UserRole.SUPER_ADMIN)),
            User.fcm_token.isnot(None),
        )
        .all()
    )
    notify_users(
        admins,
        title="Новая заявка на отсутствие",
        body=f"{current_user.full_name} подал(а) заявку на {data.request_type.value}",
        data={"type": "absence_request_new", "request_id": str(req.id)},
    )

    return req


@router.get("/my", response_model=List[AbsenceRequestResponse])
def list_my_absence_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(AbsenceRequest)
        .options(joinedload(AbsenceRequest.user))
        .filter(AbsenceRequest.user_id == current_user.id)
        .order_by(AbsenceRequest.created_at.desc())
        .all()
    )


@router.get("", response_model=List[AbsenceRequestResponse])
def list_absence_requests(
    status: Optional[str] = Query(default=None),
    user_id: Optional[UUID] = Query(default=None),
    request_type: Optional[AbsenceRequestType] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    q = db.query(AbsenceRequest).options(joinedload(AbsenceRequest.user))
    if status is not None:
        if status.upper() == "PENDING":
            q = q.filter(AbsenceRequest.status == AbsenceRequestStatus.new)
        else:
            try:
                # Пытаемся преобразовать строку в Enum
                enum_status = AbsenceRequestStatus(status.lower())
                q = q.filter(AbsenceRequest.status == enum_status)
            except ValueError:
                # Если статус неизвестен, просто не фильтруем по нему (или можно выдать ошибку)
                pass
    if user_id is not None:
        q = q.filter(AbsenceRequest.user_id == user_id)
    if request_type is not None:
        q = q.filter(AbsenceRequest.request_type == request_type)

    return q.order_by(AbsenceRequest.created_at.desc()).all()


@router.get("/{request_id}", response_model=AbsenceRequestResponse)
def get_absence_request(
    request_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    req = (
        db.query(AbsenceRequest)
        .options(joinedload(AbsenceRequest.user))
        .filter(AbsenceRequest.id == request_id)
        .first()
    )
    if not req:
        raise HTTPException(status_code=404, detail="Заявка не найдена")
    return req


@router.patch("/{request_id}/review", response_model=AbsenceRequestResponse)
def review_absence_request(
    request_id: UUID,
    data: AbsenceRequestReview,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    req = (
        db.query(AbsenceRequest)
        .options(joinedload(AbsenceRequest.user))
        .filter(AbsenceRequest.id == request_id)
        .first()
    )
    if not req:
        raise HTTPException(status_code=404, detail="Заявка не найдена")

    req.status = data.status
    req.comment_admin = data.comment_admin
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)

    if data.status == AbsenceRequestStatus.approved:
        _apply_request_to_attendance(db, req, current_user)

    db.commit()
    req = (
        db.query(AbsenceRequest)
        .options(joinedload(AbsenceRequest.user))
        .filter(AbsenceRequest.id == req.id)
        .first()
    )

    # Push notification → сотруднику о результате
    if data.status == AbsenceRequestStatus.approved:
        notify_user(
            req.user,
            title="Заявка одобрена",
            body="Ваша заявка на отсутствие одобрена",
            data={"type": "absence_request_approved", "request_id": str(req.id)},
        )
    elif data.status == AbsenceRequestStatus.rejected:
        notify_user(
            req.user,
            title="Заявка отклонена",
            body=data.comment_admin or "Ваша заявка на отсутствие отклонена",
            data={"type": "absence_request_rejected", "request_id": str(req.id)},
        )

    return req

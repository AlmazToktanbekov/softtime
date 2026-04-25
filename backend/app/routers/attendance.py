from datetime import date, datetime
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Union

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.models.attendance import Attendance, AttendanceStatus, CheckInStatus, CheckOutStatus
from app.models.employee_schedule import EmployeeSchedule
from app.schemas.attendance import (
    CheckInRequest,
    CheckOutRequest,
    AttendanceManualUpdate,
    AttendanceAdminCloseRequest,
    AttendanceResponse,
    MarkApprovedAbsenceRequest,
)
from app.utils.dependencies import get_current_user, require_admin
from app.utils.audit import write_audit
from app.services.ip_service import get_client_ip, validate_office_network
from app.services.qr_service import validate_qr_token
from app.services.attendance_service import (
    process_check_in,
    process_check_out,
    log_action,
    admin_close_attendance,
)

router = APIRouter(prefix="/attendance", tags=["Посещаемость"])


def _fmt_time(dt) -> Optional[str]:
    if dt is None:
        return None
    if dt.tzinfo is not None:
        return dt.astimezone().strftime("%H:%M")
    return dt.strftime("%H:%M")


def _to_naive_local(dt: datetime) -> datetime:
    """Convert tz-aware datetime to naive local time for schedule comparison."""
    if dt.tzinfo is not None:
        return dt.astimezone().replace(tzinfo=None)
    return dt


def _serialize(a: Attendance, db: Session) -> AttendanceResponse:
    user = db.query(User).filter(User.id == a.user_id).first()
    fmt_in = _fmt_time(a.check_in_time)
    fmt_out = _fmt_time(a.check_out_time)

    late_minutes = 0
    early_arrival_minutes = 0
    early_leave_minutes = 0
    overtime_minutes = 0

    if a.date and a.check_in_time:
        schedule = (
            db.query(EmployeeSchedule)
            .filter(
                EmployeeSchedule.user_id == a.user_id,
                EmployeeSchedule.day_of_week == a.date.weekday(),
            )
            .first()
        )
        if schedule and schedule.is_working_day:
            check_in_naive = _to_naive_local(a.check_in_time)

            # Рассчитываем опоздание / ранний приход
            if schedule.start_time:
                expected_start = datetime.combine(a.date, schedule.start_time)
                diff_in = int((check_in_naive - expected_start).total_seconds() // 60)
                if diff_in > 0:
                    late_minutes = diff_in
                elif diff_in < 0:
                    early_arrival_minutes = -diff_in

            # Рассчитываем ранний уход / сверхурочные
            if schedule.end_time and a.check_out_time:
                check_out_naive = _to_naive_local(a.check_out_time)
                expected_end = datetime.combine(a.date, schedule.end_time)
                diff_out = int((check_out_naive - expected_end).total_seconds() // 60)
                if diff_out < 0:
                    early_leave_minutes = -diff_out
                elif diff_out > 0:
                    overtime_minutes = diff_out

    return AttendanceResponse(
        id=a.id,
        user_id=a.user_id,
        employee_name=user.full_name if user else None,
        date=a.date,
        check_in_time=a.check_in_time,
        check_out_time=a.check_out_time,
        formatted_check_in=fmt_in,
        formatted_check_out=fmt_out,
        work_duration=a.work_duration,
        work_minutes=a.work_minutes,
        status=a.status,
        late_minutes=late_minutes,
        early_arrival_minutes=early_arrival_minutes,
        early_leave_minutes=early_leave_minutes,
        overtime_minutes=overtime_minutes,
        underwork_minutes=0,
        is_late=late_minutes > 0,
        came_early=early_arrival_minutes > 0,
        left_early=early_leave_minutes > 0,
        left_late=overtime_minutes > 0,
        check_in_ip=a.check_in_ip,
        check_out_ip=a.check_out_ip,
        qr_verified_in=bool(a.qr_verified_in),
        qr_verified_out=bool(a.qr_verified_out),
        office_network_id=a.office_network_id,
        note=a.note,
    )


@router.post("/check-in", response_model=AttendanceResponse)
def check_in(
    data: CheckInRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ip_address = get_client_ip(request)

    qr_valid, qr_msg = validate_qr_token(data.qr_token, db, expected_type="attendance")
    if not qr_valid:
        log_action(current_user.id, "check_in", "failure", qr_msg, ip_address, db)
        raise HTTPException(status_code=400, detail=qr_msg)

    network_valid, office_network = validate_office_network(ip_address, db)
    if not network_valid:
        msg = "Вы не подключены к офисной сети"
        log_action(current_user.id, "check_in", "failure", msg, ip_address, db)
        raise HTTPException(status_code=403, detail=msg)

    network_id = office_network.id if office_network and office_network.id != 0 else None
    success, message, attendance = process_check_in(current_user, ip_address, network_id, db)

    if not success or attendance is None:
        log_action(current_user.id, "check_in", "failure", message, ip_address, db)
        raise HTTPException(status_code=400, detail=message)

    # Геймификация: +10 очков за приход в офис
    from app.routers.extras import _add_points
    _add_points(db, current_user.id, 10, "Посещение офиса")
    db.commit()

    return _serialize(attendance, db)


@router.post("/check-out", response_model=AttendanceResponse)
def check_out(
    data: CheckOutRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ip_address = get_client_ip(request)

    qr_valid, qr_msg = validate_qr_token(data.qr_token, db, expected_type="attendance")
    if not qr_valid:
        raise HTTPException(status_code=400, detail=qr_msg)

    network_valid, office_network = validate_office_network(ip_address, db)
    if not network_valid:
        raise HTTPException(status_code=403, detail="Вы не подключены к офисной сети")

    network_id = office_network.id if office_network and office_network.id != 0 else None
    success, message, attendance = process_check_out(current_user, ip_address, network_id, db)

    if not success or attendance is None:
        raise HTTPException(status_code=400, detail=message)

    return _serialize(attendance, db)


@router.get("/my", response_model=List[AttendanceResponse])
def my_attendance(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(Attendance).filter(Attendance.user_id == current_user.id)
    if start_date:
        q = q.filter(Attendance.date >= start_date)
    if end_date:
        q = q.filter(Attendance.date <= end_date)
    rows = q.order_by(Attendance.date.desc()).all()
    return [_serialize(r, db) for r in rows]


@router.get("", response_model=List[AttendanceResponse])
def all_attendance(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    user_id: Optional[UUID] = None,
    status: Optional[AttendanceStatus] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    q = db.query(Attendance).join(User, Attendance.user_id == User.id)
    if user_id:
        q = q.filter(Attendance.user_id == user_id)
    if start_date:
        q = q.filter(Attendance.date >= start_date)
    if end_date:
        q = q.filter(Attendance.date <= end_date)
    if status:
        q = q.filter(Attendance.status == status)
    rows = q.order_by(Attendance.date.desc(), Attendance.id.desc()).all()
    return [_serialize(r, db) for r in rows]


@router.get("/by-user/{user_id}", response_model=List[AttendanceResponse])
def user_attendance(
    user_id: UUID,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    q = db.query(Attendance).filter(Attendance.user_id == user_id)
    if start_date:
        q = q.filter(Attendance.date >= start_date)
    if end_date:
        q = q.filter(Attendance.date <= end_date)
    rows = q.order_by(Attendance.date.desc()).all()
    return [_serialize(r, db) for r in rows]


@router.patch("/{attendance_id}/manual-update", response_model=AttendanceResponse)
def manual_update(
    attendance_id: UUID,
    data: AttendanceManualUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(Attendance).filter(Attendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    if data.check_in_time is not None:
        record.check_in_time = data.check_in_time
    if data.check_out_time is not None:
        record.check_out_time = data.check_out_time
    if data.note is not None:
        record.note = data.note

    record.qr_verified_in = False
    record.qr_verified_out = False
    record.check_in_ip = None
    record.check_out_ip = None
    record.status = AttendanceStatus.MANUAL
    record.is_manual = True
    record.manual_by = current_user.id

    write_audit(db, actor_id=current_user.id, action="MANUAL_UPDATE",
                entity="Attendance", entity_id=attendance_id,
                new_value=data.model_dump(mode="json"))
    db.commit()
    db.refresh(record)
    return _serialize(record, db)


@router.patch("/{attendance_id}/admin-close", response_model=AttendanceResponse)
def admin_close(
    attendance_id: UUID,
    data: AttendanceAdminCloseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(Attendance).filter(Attendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    if not record.check_in_time:
        raise HTTPException(status_code=400, detail="Нельзя закрыть день без времени прихода")
    if record.check_out_time:
        raise HTTPException(status_code=400, detail="Уход уже отмечен")

    record = admin_close_attendance(record, data.check_out_time, data.note, db)
    write_audit(db, actor_id=current_user.id, action="ADMIN_CLOSE",
                entity="Attendance", entity_id=attendance_id,
                new_value={"check_out_time": str(data.check_out_time), "note": data.note})
    db.commit()
    return _serialize(record, db)


class ManualCheckoutRequest(BaseModel):
    check_out_time: datetime
    note: Union[str, None] = None


@router.patch("/{attendance_id}/manual-checkout", response_model=AttendanceResponse)
def manual_checkout(
    attendance_id: UUID,
    data: ManualCheckoutRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    record = db.query(Attendance).filter(Attendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    if not record.check_in_time:
        raise HTTPException(status_code=400, detail="Нельзя поставить уход без прихода")

    check_in_naive = record.check_in_time.replace(tzinfo=None) if record.check_in_time.tzinfo else record.check_in_time
    check_out_naive = data.check_out_time.replace(tzinfo=None) if data.check_out_time.tzinfo else data.check_out_time
    if check_out_naive <= check_in_naive:
        raise HTTPException(status_code=400, detail="Время ухода должно быть позже времени прихода")

    record.check_out_time = data.check_out_time
    record.check_out_ip = None
    record.qr_verified_out = False
    record.status = AttendanceStatus.MANUAL
    record.is_manual = True
    record.manual_by = current_user.id
    if data.note:
        record.note = data.note

    write_audit(db, actor_id=current_user.id, action="MANUAL_CHECKOUT",
                entity="Attendance", entity_id=attendance_id,
                new_value={"check_out_time": str(data.check_out_time), "note": data.note})
    db.commit()
    db.refresh(record)
    return _serialize(record, db)


@router.post("/approved-absence", response_model=AttendanceResponse)
def mark_approved_absence(
    data: MarkApprovedAbsenceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    user = db.query(User).filter(User.id == data.user_id, User.deleted_at.is_(None)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    record = (
        db.query(Attendance)
        .filter(Attendance.user_id == data.user_id, Attendance.date == data.date)
        .first()
    )

    if record:
        record.status = AttendanceStatus.APPROVED_ABSENCE
        record.note = data.note
        record.check_in_time = None
        record.check_out_time = None
        record.check_in_ip = None
        record.check_out_ip = None
        record.qr_verified_in = False
        record.qr_verified_out = False
        record.late_minutes = 0
    else:
        record = Attendance(
            user_id=data.user_id,
            date=data.date,
            status=AttendanceStatus.APPROVED_ABSENCE,
            note=data.note,
        )
        db.add(record)

    db.commit()
    db.refresh(record)
    return _serialize(record, db)



@router.get("/in-office", response_model=List[AttendanceResponse])
def who_is_in_office(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Кто сейчас в офисе: check_in есть, check_out нет, статус PRESENT или LATE (ТЗ §2.5)."""
    today = date.today()
    admin_ids = db.query(User.id).filter(
        User.role.in_([UserRole.ADMIN, UserRole.SUPER_ADMIN])
    ).subquery()
    rows = (
        db.query(Attendance)
        .filter(
            Attendance.date == today,
            Attendance.check_in_time.isnot(None),
            Attendance.check_out_time.is_(None),
            Attendance.status.in_([AttendanceStatus.PRESENT, AttendanceStatus.LATE]),
            Attendance.user_id.notin_(admin_ids),
        )
        .all()
    )
    return [_serialize(r, db) for r in rows]


@router.get("/today-status")
def today_office_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Статус офиса на сегодня — доступен всем сотрудникам."""
    today = date.today()

    non_admin_users = (
        db.query(User)
        .filter(
            User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
            User.status.in_([UserStatus.ACTIVE, UserStatus.LEAVE, UserStatus.WARNING]),
            User.deleted_at.is_(None),
        )
        .all()
    )
    non_admin_ids = {u.id for u in non_admin_users}
    user_map = {u.id: u.full_name for u in non_admin_users}

    records = (
        db.query(Attendance)
        .filter(Attendance.date == today, Attendance.user_id.in_(non_admin_ids))
        .all()
    )
    checked_in_ids = {r.user_id for r in records if r.check_in_time}

    in_office, left, not_arrived = [], [], []

    for r in records:
        name = user_map.get(r.user_id, "—")
        entry = {
            "user_id": str(r.user_id),
            "name": name,
            "check_in_time": _fmt_time(r.check_in_time),
            "check_out_time": _fmt_time(r.check_out_time),
        }
        if r.check_in_time and not r.check_out_time:
            in_office.append(entry)
        elif r.check_in_time and r.check_out_time:
            left.append(entry)

    for uid, name in user_map.items():
        if uid not in checked_in_ids:
            not_arrived.append({"user_id": str(uid), "name": name})

    return {
        "in_office": in_office,
        "left": left,
        "not_arrived": not_arrived,
        "total": len(non_admin_users),
        "in_office_count": len(in_office),
        "left_count": len(left),
        "not_arrived_count": len(not_arrived),
    }

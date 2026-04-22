from datetime import datetime, date
from typing import Optional, Tuple
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.attendance import Attendance, AttendanceStatus, CheckInStatus, CheckOutStatus
from app.models.attendance_log import AttendanceLog
from app.models.user import User, UserStatus
from app.models.work_settings import WorkSettings
from app.models.employee_schedule import EmployeeSchedule


def _today() -> date:
    return datetime.now().date()


def get_or_create_work_settings(db: Session) -> WorkSettings:
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


def get_user_schedule(user_id: UUID, target_date: date, db: Session) -> Optional[EmployeeSchedule]:
    day_of_week = target_date.weekday()
    return (
        db.query(EmployeeSchedule)
        .filter(
            EmployeeSchedule.user_id == user_id,
            EmployeeSchedule.day_of_week == day_of_week,
        )
        .first()
    )


def process_check_in(
    user: User,
    ip_address: str,
    office_network_id: Optional[int],
    db: Session,
) -> Tuple[bool, str, Optional[Attendance]]:
    if user.status == UserStatus.PENDING:
        return False, "Ожидайте подтверждения администратора", None
    if user.status == UserStatus.LEAVE:
        return False, "В отпуске нельзя отмечать приход", None

    today = _today()
    now = datetime.now().astimezone()

    existing = (
        db.query(Attendance)
        .filter(Attendance.user_id == user.id, Attendance.date == today)
        .first()
    )

    if existing and existing.check_in_time:
        return False, "Приход уже отмечен", None

    if not existing:
        record = Attendance(user_id=user.id, date=today)
        db.add(record)
        db.flush()
    else:
        record = existing

    schedule = get_user_schedule(user.id, today, db)
    record._schedule = schedule

    late_minutes = 0
    check_in_st = CheckInStatus.ON_TIME
    if schedule and schedule.is_working_day and schedule.start_time:
        expected_dt = datetime.combine(today, schedule.start_time, tzinfo=now.tzinfo)
        diff = int((now - expected_dt).total_seconds() // 60)
        settings = get_or_create_work_settings(db)
        grace = settings.grace_period_minutes
        late_minutes = max(diff - grace, 0)
        if diff < 0:
            check_in_st = CheckInStatus.EARLY_ARRIVAL
        elif late_minutes > 0:
            check_in_st = CheckInStatus.LATE
        else:
            check_in_st = CheckInStatus.ON_TIME
    else:
        late_minutes = 0
        check_in_st = CheckInStatus.ON_TIME

    record.check_in_time = now
    record.check_in_status = check_in_st
    record.check_in_ip = ip_address
    record.qr_verified_in = True
    record.office_network_id = office_network_id
    record.late_minutes = late_minutes
    record.status = AttendanceStatus.LATE if late_minutes > 0 else AttendanceStatus.PRESENT

    db.commit()
    db.refresh(record)

    log_action(user.id, "check_in", "success", "Приход отмечен", ip_address, db)

    return True, "Приход отмечен", record


def process_check_out(
    user: User,
    ip_address: str,
    office_network_id: Optional[int],
    db: Session,
) -> Tuple[bool, str, Optional[Attendance]]:
    if user.status == UserStatus.PENDING:
        return False, "Ожидайте подтверждения администратора", None
    if user.status == UserStatus.LEAVE:
        return False, "В отпуске нельзя отмечать уход", None

    today = _today()
    now = datetime.now().astimezone()

    record = (
        db.query(Attendance)
        .filter(Attendance.user_id == user.id, Attendance.date == today)
        .first()
    )

    if not record or not record.check_in_time:
        return False, "Сначала нужно отметить приход", None

    if record.check_out_time:
        return False, "Уход уже отмечен", None

    schedule = getattr(record, "_schedule", None)
    if schedule is None:
        schedule = get_user_schedule(user.id, today, db)
        record._schedule = schedule

    record.check_out_time = now
    record.check_out_ip = ip_address
    record.qr_verified_out = True
    record.office_network_id = office_network_id

    # Определяем статус ухода по расписанию (независимо от статуса прихода)
    check_out_st = CheckOutStatus.ON_TIME
    if schedule and schedule.is_working_day and schedule.end_time:
        expected_end = datetime.combine(today, schedule.end_time, tzinfo=now.tzinfo)
        if now < expected_end:
            check_out_st = CheckOutStatus.LEFT_EARLY
        elif now > expected_end:
            check_out_st = CheckOutStatus.OVERTIME

    record.check_out_status = check_out_st

    # LATE сохраняется если опоздал, иначе определяем по уходу
    was_late = record.status == AttendanceStatus.LATE
    if was_late:
        final_status = AttendanceStatus.LATE
    elif check_out_st == CheckOutStatus.LEFT_EARLY:
        final_status = AttendanceStatus.EARLY_LEAVE
    elif check_out_st == CheckOutStatus.OVERTIME:
        final_status = AttendanceStatus.OVERTIME
    else:
        final_status = AttendanceStatus.PRESENT

    record.status = final_status

    db.commit()
    db.refresh(record)

    log_action(user.id, "check_out", "success", "Уход отмечен", ip_address, db)

    return True, "Уход отмечен", record


def admin_close_attendance(
    record: Attendance,
    check_out_time: datetime,
    note: Optional[str],
    db: Session,
) -> Attendance:
    record.check_out_time = check_out_time
    record.qr_verified_out = False
    record.check_out_ip = None
    record.status = AttendanceStatus.MANUAL
    record.check_out_status = CheckOutStatus.ON_TIME

    if note:
        record.note = note
    else:
        base_note = record.note or ""
        extra = "Уход установлен администратором"
        record.note = f"{base_note}. {extra}".strip(". ").strip()

    db.commit()
    db.refresh(record)
    return record


def mark_incomplete_records(db: Session, target_date: Optional[date] = None) -> int:
    if target_date is None:
        target_date = _today()
    records = (
        db.query(Attendance)
        .filter(
            Attendance.date == target_date,
            Attendance.check_in_time.isnot(None),
            Attendance.check_out_time.is_(None),
            Attendance.status.in_([AttendanceStatus.PRESENT, AttendanceStatus.LATE]),
        )
        .all()
    )

    for record in records:
        record.status = AttendanceStatus.INCOMPLETE

    db.commit()
    return len(records)


def log_action(
    user_id: UUID,
    action: str,
    result: str,
    message: str,
    ip_address: Optional[str],
    db: Session,
):
    log = AttendanceLog(
        user_id=user_id,
        action=action,
        result=result,
        message=message,
        ip_address=ip_address,
    )
    db.add(log)
    db.commit()

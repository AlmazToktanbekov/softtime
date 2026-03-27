from datetime import datetime, date, time
from typing import Optional, Tuple
from sqlalchemy.orm import Session

from app.models.attendance import Attendance, AttendanceStatus
from app.models.attendance_log import AttendanceLog
from app.models.employee import Employee
from app.models.work_settings import WorkSettings


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


def _minutes_late(check_in_time: datetime, db: Session) -> int:
    settings = get_or_create_work_settings(db)

    start_hour = settings.work_start_hour
    start_minute = settings.work_start_minute
    grace = settings.grace_period_minutes

    expected = datetime.combine(
        check_in_time.date(),
        time(start_hour, start_minute),
        tzinfo=check_in_time.tzinfo
    )
    diff = int((check_in_time - expected).total_seconds() // 60)
    return max(diff - grace, 0)


def process_check_in(
    employee: Employee,
    ip_address: str,
    office_network_id: Optional[int],
    db: Session,
) -> Tuple[bool, str, Optional[Attendance]]:
    today = _today()
    now = datetime.now().astimezone()

    existing = db.query(Attendance).filter(
        Attendance.employee_id == employee.id,
        Attendance.date == today
    ).first()

    if existing and existing.check_in_time:
        return False, "Приход уже отмечен", None

    if not existing:
        record = Attendance(
            employee_id=employee.id,
            date=today,
        )
        db.add(record)
        db.flush()
    else:
        record = existing

    late_minutes = _minutes_late(now, db)

    record.check_in_time = now
    record.check_in_ip = ip_address
    record.qr_verified_in = True
    record.office_network_id = office_network_id
    record.late_minutes = late_minutes
    record.status = AttendanceStatus.late if late_minutes > 0 else AttendanceStatus.present

    db.commit()
    db.refresh(record)

    log_action(employee.id, "check_in", "success", "Приход отмечен", ip_address, db)

    return True, "Приход отмечен", record


def process_check_out(
    employee: Employee,
    ip_address: str,
    office_network_id: Optional[int],
    db: Session,
) -> Tuple[bool, str, Optional[Attendance]]:
    today = _today()
    now = datetime.now().astimezone()

    record = db.query(Attendance).filter(
        Attendance.employee_id == employee.id,
        Attendance.date == today
    ).first()

    if not record or not record.check_in_time:
        return False, "Сначала нужно отметить приход", None

    if record.check_out_time:
        return False, "Уход уже отмечен", None

    record.check_out_time = now
    record.check_out_ip = ip_address
    record.qr_verified_out = True
    record.office_network_id = office_network_id
    record.status = AttendanceStatus.completed

    db.commit()
    db.refresh(record)

    log_action(employee.id, "check_out", "success", "Уход отмечен", ip_address, db)

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
    record.status = AttendanceStatus.manual

    if note:
        record.note = note
    else:
        base_note = record.note or ""
        extra = "Уход установлен администратором"
        record.note = f"{base_note}. {extra}".strip(". ").strip()

    db.commit()
    db.refresh(record)
    return record


def mark_incomplete_records(db: Session) -> int:
    records = db.query(Attendance).filter(
        Attendance.check_in_time.isnot(None),
        Attendance.check_out_time.is_(None),
        Attendance.status.in_([AttendanceStatus.present, AttendanceStatus.late])
    ).all()

    for record in records:
        record.status = AttendanceStatus.incomplete

    db.commit()
    return len(records)


def log_action(
    employee_id: int,
    action: str,
    result: str,
    message: str,
    ip_address: Optional[str],
    db: Session
):
    log = AttendanceLog(
        employee_id=employee_id,
        action=action,
        result=result,
        message=message,
        ip_address=ip_address,
    )
    db.add(log)
    db.commit()
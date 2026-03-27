from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date

from pydantic import BaseModel
from datetime import datetime

from app.database import get_db
from app.models.user import User, UserRole
from app.models.employee import Employee
from app.models.attendance import Attendance, AttendanceStatus
from app.schemas.attendance import (
    CheckInRequest,
    CheckOutRequest,
    AttendanceManualUpdate,
    AttendanceAdminCloseRequest,
    AttendanceResponse,
    MarkApprovedAbsenceRequest,
)
from app.utils.dependencies import get_current_user, require_admin
from app.services.ip_service import get_client_ip, validate_office_network
from app.services.qr_service import validate_qr_token
from app.services.attendance_service import (
    process_check_in,
    process_check_out,
    log_action,
    admin_close_attendance,
)

router = APIRouter(prefix="/attendance", tags=["Посещаемость"])


def get_employee_or_403(user: User, db: Session) -> Employee:
    if not user.employee_id:
        raise HTTPException(status_code=400, detail="Профиль сотрудника не найден")
    emp = db.query(Employee).filter(
        Employee.id == user.employee_id,
        Employee.is_active == True
    ).first()
    if not emp:
        raise HTTPException(status_code=400, detail="Сотрудник не найден или неактивен")
    return emp


@router.post("/check-in", response_model=AttendanceResponse)
def check_in(
    data: CheckInRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    employee = get_employee_or_403(current_user, db)
    ip_address = get_client_ip(request)
    print("CHECK-IN CLIENT IP =", ip_address)

    qr_valid, qr_msg = validate_qr_token(data.qr_token, db)
    if not qr_valid:
        log_action(employee.id, "check_in", "failure", qr_msg, ip_address, db)
        raise HTTPException(status_code=400, detail=qr_msg)

    network_valid, office_network = validate_office_network(ip_address, db)
    if not network_valid:
        msg = "Вы не подключены к офисной сети"
        log_action(employee.id, "check_in", "failure", msg, ip_address, db)
        raise HTTPException(status_code=403, detail=msg)

    network_id = office_network.id if office_network and office_network.id != 0 else None
    success, message, attendance = process_check_in(employee, ip_address, network_id, db)

    if not success:
        log_action(employee.id, "check_in", "failure", message, ip_address, db)
        raise HTTPException(status_code=400, detail=message)

    return attendance


@router.post("/check-out", response_model=AttendanceResponse)
def check_out(
    data: CheckOutRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    employee = get_employee_or_403(current_user, db)
    ip_address = get_client_ip(request)
    print("CHECK-OUT CLIENT IP =", ip_address)

    qr_valid, qr_msg = validate_qr_token(data.qr_token, db)
    if not qr_valid:
        raise HTTPException(status_code=400, detail=qr_msg)

    network_valid, office_network = validate_office_network(ip_address, db)
    if not network_valid:
        raise HTTPException(status_code=403, detail="Вы не подключены к офисной сети")

    network_id = office_network.id if office_network and office_network.id != 0 else None
    success, message, attendance = process_check_out(employee, ip_address, network_id, db)

    if not success:
        raise HTTPException(status_code=400, detail=message)

    return attendance


@router.get("/my", response_model=List[AttendanceResponse])
def my_attendance(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if not current_user.employee_id:
        raise HTTPException(status_code=400, detail="Профиль сотрудника не найден")

    query = db.query(Attendance).filter(Attendance.employee_id == current_user.employee_id)

    if start_date:
        query = query.filter(Attendance.date >= start_date)
    if end_date:
        query = query.filter(Attendance.date <= end_date)

    return query.order_by(Attendance.date.desc()).all()


@router.get("", response_model=List[AttendanceResponse])
def all_attendance(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    employee_id: Optional[int] = None,
    department: Optional[str] = None,
    status: Optional[AttendanceStatus] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    query = db.query(Attendance).join(Employee)

    if employee_id:
        query = query.filter(Attendance.employee_id == employee_id)
    if start_date:
        query = query.filter(Attendance.date >= start_date)
    if end_date:
        query = query.filter(Attendance.date <= end_date)
    if department:
        query = query.filter(Employee.department == department)
    if status:
        query = query.filter(Attendance.status == status)

    return query.order_by(Attendance.date.desc(), Attendance.id.desc()).all()


@router.get("/{employee_id}", response_model=List[AttendanceResponse])
def employee_attendance(
    employee_id: int,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    query = db.query(Attendance).filter(Attendance.employee_id == employee_id)

    if start_date:
        query = query.filter(Attendance.date >= start_date)
    if end_date:
        query = query.filter(Attendance.date <= end_date)

    return query.order_by(Attendance.date.desc()).all()


@router.patch("/{attendance_id}/manual-update", response_model=AttendanceResponse)
def manual_update(
    attendance_id: int,
    data: AttendanceManualUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
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
    record.status = AttendanceStatus.manual

    db.commit()
    db.refresh(record)
    return record


@router.patch("/{attendance_id}/admin-close", response_model=AttendanceResponse)
def admin_close(
    attendance_id: int,
    data: AttendanceAdminCloseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    record = db.query(Attendance).filter(Attendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    if not record.check_in_time:
        raise HTTPException(status_code=400, detail="Нельзя закрыть день без времени прихода")

    if record.check_out_time:
        raise HTTPException(status_code=400, detail="Уход уже отмечен")

    record = admin_close_attendance(record, data.check_out_time, data.note, db)
    return record


class ManualCheckoutRequest(BaseModel):
    check_out_time: datetime
    note: str | None = None

@router.patch("/{attendance_id}/manual-checkout", response_model=AttendanceResponse)
def manual_checkout(
    attendance_id: int,
    data: ManualCheckoutRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    record = db.query(Attendance).filter(Attendance.id == attendance_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    if not record.check_in_time:
        raise HTTPException(status_code=400, detail="Нельзя поставить уход без прихода")

    record.check_out_time = data.check_out_time
    record.check_out_ip = None
    record.qr_verified_out = False
    record.status = AttendanceStatus.manual

    if data.note:
        record.note = data.note

    db.commit()
    db.refresh(record)
    return record


@router.post("/mark-approved-absence", response_model=AttendanceResponse)
def mark_approved_absence(
    data: MarkApprovedAbsenceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    """Админ отмечает, что сотруднику дано разрешение не прийти (с комментарием)."""
    emp = db.query(Employee).filter(
        Employee.id == data.employee_id,
        Employee.is_active == True
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Сотрудник не найден или неактивен")

    record = db.query(Attendance).filter(
        Attendance.employee_id == data.employee_id,
        Attendance.date == data.date
    ).first()

    if record:
        record.status = AttendanceStatus.approved_absence
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
            employee_id=data.employee_id,
            date=data.date,
            status=AttendanceStatus.approved_absence,
            note=data.note,
        )
        db.add(record)

    db.commit()
    db.refresh(record)
    return record
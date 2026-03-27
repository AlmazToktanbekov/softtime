from pydantic import BaseModel, ConfigDict
from typing import Optional
from datetime import datetime, date
from app.models.attendance import AttendanceStatus


class CheckInRequest(BaseModel):
    qr_token: str


class CheckOutRequest(BaseModel):
    qr_token: str


class AttendanceManualUpdate(BaseModel):
    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None
    note: Optional[str] = None


class AttendanceAdminCloseRequest(BaseModel):
    check_out_time: datetime
    note: Optional[str] = None


class MarkApprovedAbsenceRequest(BaseModel):
    """Админ указывает, что сотруднику дано разрешение не прийти (с комментарием)."""
    employee_id: int
    date: date
    note: str  # Комментарий (причина): больничный, отпуск, удалёнка и т.д.


class AttendanceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    employee_id: int
    employee_name: Optional[str] = None
    date: date

    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None

    formatted_check_in: Optional[str] = None
    formatted_check_out: Optional[str] = None
    work_duration: Optional[str] = None
    work_minutes: int = 0

    status: AttendanceStatus
    late_minutes: int = 0
    early_arrival_minutes: int = 0
    early_leave_minutes: int = 0
    overtime_minutes: int = 0
    underwork_minutes: int = 0

    is_late: bool = False
    came_early: bool = False
    left_early: bool = False
    left_late: bool = False

    check_in_ip: Optional[str] = None
    check_out_ip: Optional[str] = None
    qr_verified_in: bool = False
    qr_verified_out: bool = False
    office_network_id: Optional[int] = None
    note: Optional[str] = None


class OfficeNetworkCreate(BaseModel):
    name: str
    public_ip: Optional[str] = None
    ip_range: Optional[str] = None
    description: Optional[str] = None


class OfficeNetworkResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    public_ip: Optional[str] = None
    ip_range: Optional[str] = None
    description: Optional[str] = None
    is_active: bool
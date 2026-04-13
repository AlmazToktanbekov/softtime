from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict  # ConfigDict used in AttendanceResponse

from app.models.attendance import AttendanceStatus


class CheckInRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")
    qr_token: str
    device_info: Optional[str] = None


class CheckOutRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")
    qr_token: str
    device_info: Optional[str] = None


class AttendanceManualUpdate(BaseModel):
    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None
    note: Optional[str] = None


class AttendanceAdminCloseRequest(BaseModel):
    check_out_time: datetime
    note: Optional[str] = None


class MarkApprovedAbsenceRequest(BaseModel):
    user_id: UUID
    date: date
    note: str


class AttendanceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    employee_name: Optional[str] = None
    date: date

    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None

    formatted_check_in: Optional[str] = None
    formatted_check_out: Optional[str] = None
    work_duration: Optional[str] = None
    work_minutes: int = 0

    status: Optional[AttendanceStatus] = None
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

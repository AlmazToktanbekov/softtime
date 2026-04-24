from app.models.team import Team
from app.models.user import User, UserRole, UserStatus
# Backward-compat aliases — old routers use these until they are rewritten
from app.models.employee import Employee, EmployeeStatus  # noqa: F401
from app.models.audit_log import AuditLog
from app.models.attendance import Attendance, AttendanceStatus, CheckInStatus, CheckOutStatus
from app.models.attendance_log import AttendanceLog
from app.models.office_network import OfficeNetwork, QRToken
from app.models.work_settings import WorkSettings
from app.models.absence_request import AbsenceRequest, AbsenceRequestType, AbsenceRequestStatus
from app.models.employee_schedule import EmployeeSchedule
from app.models.duty import DutyQueue, DutyAssignment, DutyChecklistItem, DutySwap, DutyType
from app.models.news import News, NewsRead, NewsType
from app.models.task import Task, TaskPriority, TaskStatus
from app.models.extras import (
    InternDiary, InternEvaluation,
    Room, RoomBooking,
    Kudos,
    UserPoints, PointTransaction, Reward, RewardClaim,
)

__all__ = [
    "Team",
    "User", "UserRole", "UserStatus",
    "AuditLog",
    "Attendance", "AttendanceStatus", "CheckInStatus", "CheckOutStatus",
    "AttendanceLog",
    "OfficeNetwork", "QRToken",
    "WorkSettings",
    "AbsenceRequest", "AbsenceRequestType", "AbsenceRequestStatus",
    "EmployeeSchedule",
    "DutyQueue", "DutyAssignment", "DutyChecklistItem", "DutySwap", "DutyType",
    "News", "NewsRead", "NewsType",
    "Task", "TaskPriority", "TaskStatus",
    "InternDiary", "InternEvaluation",
    "Room", "RoomBooking",
    "Kudos",
    "UserPoints", "PointTransaction", "Reward", "RewardClaim",
]

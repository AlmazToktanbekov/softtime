from datetime import date, datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.models.duty import DutyType


class DutyQueueResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    queue_order: int
    created_at: datetime


class DutyAssignmentCreate(BaseModel):
    user_id: UUID
    date: date
    duty_type: DutyType = DutyType.LUNCH


class DutyAssignmentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    user_full_name: Optional[str] = None
    date: date
    duty_type: DutyType
    is_completed: bool
    completion_tasks: Optional[List] = None
    completion_qr_verified: bool
    completed_at: Optional[datetime] = None
    verified: bool
    verified_by: Optional[UUID] = None
    verified_at: Optional[datetime] = None
    admin_note: Optional[str] = None
    created_at: datetime


class DutyCompletionSubmit(BaseModel):
    tasks: List[UUID]
    qr_token: str


class DutyCompletionResponse(BaseModel):
    message: str
    assignment_id: UUID


class DutyVerifyRequest(BaseModel):
    approve: bool
    admin_note: Optional[str] = None


class DutySwapCreate(BaseModel):
    target_user_id: UUID
    assignment_id: UUID
    # Взаимный обмен: назначение коллеги (тот же duty_type). Если null — дежурство просто передаётся адресату.
    target_assignment_id: Optional[UUID] = None


class DutySwapResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    requester_id: UUID
    requester_name: Optional[str] = None
    target_id: UUID
    target_name: Optional[str] = None
    assignment_id: UUID
    target_assignment_id: Optional[UUID] = None
    duty_type: Optional[DutyType] = None
    duty_date: Optional[date] = None
    target_peer_date: Optional[date] = None
    status: str
    response_note: Optional[str] = None
    responded_by: Optional[UUID] = None
    responded_at: Optional[datetime] = None
    created_at: datetime

    @classmethod
    def from_orm_with_names(cls, swap):
        return cls(
            id=swap.id,
            requester_id=swap.requester_id,
            requester_name=swap.requester.full_name if swap.requester else None,
            target_id=swap.target_id,
            target_name=swap.target.full_name if swap.target else None,
            assignment_id=swap.assignment_id,
            target_assignment_id=swap.target_assignment_id,
            duty_type=swap.assignment.duty_type if swap.assignment else None,
            duty_date=swap.assignment.date if swap.assignment else None,
            target_peer_date=swap.target_assignment.date if swap.target_assignment else None,
            status=swap.status,
            response_note=swap.response_note,
            responded_by=swap.responded_by,
            responded_at=swap.responded_at,
            created_at=swap.created_at,
        )


class DutyChecklistItemCreate(BaseModel):
    text: str
    order: int = 0
    duty_type: Optional[DutyType] = None   # None = shared for both types


class DutyChecklistItemUpdate(BaseModel):
    text: Optional[str] = None
    order: Optional[int] = None
    is_active: Optional[bool] = None
    duty_type: Optional[DutyType] = None


class DutyChecklistItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    text: str
    order: int
    is_active: bool
    duty_type: Optional[DutyType] = None
    created_at: datetime


# ── Weekly lunch schedule ─────────────────────────────────────────────────────

class WeeklyLunchScheduleEntry(BaseModel):
    """One day of the weekly lunch duty schedule."""
    weekday: int          # 0=Monday … 6=Sunday
    user_id: Optional[UUID] = None


class WeeklyLunchScheduleRequest(BaseModel):
    """Admin submits 7 entries (Mon–Sun) to set who does lunch each day."""
    week_start: date      # Monday of the target week
    entries: List[WeeklyLunchScheduleEntry]


# ── Admin duty overview ───────────────────────────────────────────────────────

class DutyOverviewEntry(BaseModel):
    date: date
    duty_type: DutyType
    user_id: Optional[UUID] = None
    user_full_name: Optional[str] = None
    is_completed: bool = False
    verified: bool = False

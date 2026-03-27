from datetime import date, time, datetime
from typing import Optional, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.models.absence_request import (
    AbsenceRequestType,
    AbsenceRequestStatus,
)


class AbsenceRequestCreate(BaseModel):
    request_type: AbsenceRequestType
    start_date: date
    end_date: Optional[date] = None
    start_time: Optional[time] = None
    comment_employee: Optional[str] = Field(default=None, max_length=1000)


class AbsenceRequestReview(BaseModel):
    status: Literal[
        AbsenceRequestStatus.approved,
        AbsenceRequestStatus.rejected,
        AbsenceRequestStatus.needs_clarification,
        AbsenceRequestStatus.reviewing,
    ]
    comment_admin: Optional[str] = Field(default=None, max_length=1000)


class AbsenceRequestResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    employee_id: int
    request_type: AbsenceRequestType
    start_date: date
    end_date: Optional[date] = None
    start_time: Optional[time] = None
    comment_employee: Optional[str] = None
    comment_admin: Optional[str] = None
    status: AbsenceRequestStatus
    reviewed_by: Optional[int] = None
    reviewed_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


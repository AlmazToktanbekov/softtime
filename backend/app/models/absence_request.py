from datetime import date, time, datetime
from enum import Enum

from sqlalchemy import (
    Column,
    Integer,
    String,
    Date,
    Time,
    Enum as SQLEnum,
    ForeignKey,
    DateTime,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class AbsenceRequestType(str, Enum):
    sick = "sick"
    family = "family"
    vacation = "vacation"
    business_trip = "business_trip"
    remote_work = "remote_work"
    late_reason = "late_reason"
    early_leave = "early_leave"
    other = "other"


class AbsenceRequestStatus(str, Enum):
    new = "new"
    reviewing = "reviewing"
    approved = "approved"
    rejected = "rejected"
    needs_clarification = "needs_clarification"


class AbsenceRequest(Base):
    __tablename__ = "absence_requests"

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False, index=True)

    request_type = Column(SQLEnum(AbsenceRequestType), nullable=False)

    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=True)
    start_time = Column(Time, nullable=True)

    comment_employee = Column(String(1000), nullable=True)
    comment_admin = Column(String(1000), nullable=True)

    status = Column(SQLEnum(AbsenceRequestStatus), default=AbsenceRequestStatus.new, nullable=False)
    reviewed_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    employee = relationship("Employee")

    @property
    def effective_end_date(self) -> date:
        return self.end_date or self.start_date


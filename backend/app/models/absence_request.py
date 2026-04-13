import uuid
from datetime import date
from enum import Enum
from typing import Optional

from sqlalchemy import Column, String, Date, Time, Enum as SQLEnum, ForeignKey, DateTime
from sqlalchemy.dialects.postgresql import UUID
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

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    request_type = Column(SQLEnum(AbsenceRequestType), nullable=False)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=True)
    start_time = Column(Time, nullable=True)

    comment_employee = Column(String(1000), nullable=True)
    comment_admin = Column(String(1000), nullable=True)

    status = Column(
        SQLEnum(AbsenceRequestStatus),
        default=AbsenceRequestStatus.new,
        nullable=False,
    )
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="absence_requests", foreign_keys=[user_id])
    reviewer = relationship("User", foreign_keys=[reviewed_by])

    @property
    def effective_end_date(self) -> date:
        return self.end_date or self.start_date

    @property
    def user_full_name(self) -> Optional[str]:
        if self.user is None:
            return None
        return self.user.full_name

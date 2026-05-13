import uuid
import enum
from typing import Optional

from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, Date,
    ForeignKey, JSON, Text, UniqueConstraint, Enum as SQLEnum,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class DutyType(str, enum.Enum):
    LUNCH = "LUNCH"       # Обед — каждый день, назначает Admin
    CLEANING = "CLEANING"  # Уборка — раз в неделю, назначает Admin; сотрудник сам выбирает день


class DutyQueue(Base):
    __tablename__ = "duty_queue"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True, nullable=False)
    queue_order = Column(Integer, unique=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="duty_queue_entry")


class DutyAssignment(Base):
    """
    One record per assigned duty.

    LUNCH  → `date` = конкретный день (пн, вт…)
    CLEANING → `date` = понедельник недели (week start); выполняется в любой день той недели.
    """
    __tablename__ = "duty_assignments"

    __table_args__ = (
        # One assignment per (date, duty_type) — e.g. one LUNCH and one CLEANING can share a date
        UniqueConstraint("date", "duty_type", name="uq_duty_assignment_date_type"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    date = Column(Date, nullable=False, index=True)
    duty_type = Column(SQLEnum(DutyType), nullable=False, default=DutyType.LUNCH)

    is_completed = Column(Boolean, default=False, nullable=False)
    completion_tasks = Column(JSON, nullable=True)
    completion_qr_verified = Column(Boolean, default=False, nullable=False)
    completed_at = Column(DateTime(timezone=True), nullable=True)

    verified = Column(Boolean, default=False, nullable=False)
    verified_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    admin_note = Column(Text, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="duty_assignments", foreign_keys=[user_id])
    verifier = relationship("User", foreign_keys=[verified_by])

    @property
    def user_full_name(self) -> Optional[str]:
        return self.user.full_name if self.user else None


class DutyChecklistItem(Base):
    __tablename__ = "duty_checklist_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    text = Column(String(500), nullable=False)
    order = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    # Which duty type this checklist item belongs to (None = shared)
    duty_type = Column(SQLEnum(DutyType), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())


class DutySwap(Base):
    __tablename__ = "duty_swaps"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    requester_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    target_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    assignment_id = Column(UUID(as_uuid=True), ForeignKey("duty_assignments.id"), nullable=False)
    # For mutual swap: colleague's assignment (same duty_type); on accept, user_ids are exchanged.
    target_assignment_id = Column(
        UUID(as_uuid=True), ForeignKey("duty_assignments.id", ondelete="SET NULL"), nullable=True
    )

    status = Column(String(50), default="pending")    # pending | accepted | rejected
    response_note = Column(Text, nullable=True)
    responded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    responded_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    requester = relationship("User", foreign_keys=[requester_id])
    target = relationship("User", foreign_keys=[target_id])
    assignment = relationship("DutyAssignment", foreign_keys=[assignment_id])
    target_assignment = relationship("DutyAssignment", foreign_keys=[target_assignment_id])
    responder = relationship("User", foreign_keys=[responded_by])

import uuid
from datetime import datetime, time

from sqlalchemy import Column, String, Boolean, DateTime, Date, ForeignKey, Integer, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum

from app.database import Base


class AttendanceStatus(str, enum.Enum):
    PRESENT = "PRESENT"
    LATE = "LATE"
    ABSENT = "ABSENT"
    INCOMPLETE = "INCOMPLETE"          # no check-out by 23:00
    APPROVED_ABSENCE = "APPROVED_ABSENCE"
    MANUAL = "MANUAL"                  # admin-inserted record
    EARLY_LEAVE = "EARLY_LEAVE"
    OVERTIME = "OVERTIME"


class CheckInStatus(str, enum.Enum):
    ON_TIME = "ON_TIME"
    LATE = "LATE"
    EARLY_ARRIVAL = "EARLY_ARRIVAL"


class CheckOutStatus(str, enum.Enum):
    ON_TIME = "ON_TIME"
    LEFT_EARLY = "LEFT_EARLY"
    OVERTIME = "OVERTIME"


class Attendance(Base):
    __tablename__ = "attendance"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    date = Column(Date, nullable=False, index=True)

    check_in_time = Column(DateTime(timezone=True), nullable=True)
    check_in_status = Column(SQLEnum(CheckInStatus), nullable=True)
    check_in_ip = Column(String(45), nullable=True)
    qr_verified_in = Column(Boolean, default=False)

    check_out_time = Column(DateTime(timezone=True), nullable=True)
    check_out_status = Column(SQLEnum(CheckOutStatus), nullable=True)
    check_out_ip = Column(String(45), nullable=True)
    qr_verified_out = Column(Boolean, default=False)

    late_minutes = Column(Integer, default=0)
    status = Column(SQLEnum(AttendanceStatus), nullable=True)
    office_network_id = Column(Integer, ForeignKey("office_networks.id"), nullable=True)
    note = Column(String(500), nullable=True)
    is_manual = Column(Boolean, default=False)        # True if admin manually added/edited
    manual_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="attendances", foreign_keys=[user_id])
    office_network = relationship("OfficeNetwork")
    editor = relationship("User", foreign_keys=[manual_by])

    @property
    def work_minutes(self) -> int:
        if not self.check_in_time or not self.check_out_time:
            return 0
        return max(int((self.check_out_time - self.check_in_time).total_seconds() // 60), 0)

    @property
    def work_duration(self):
        m = self.work_minutes
        if m <= 0:
            return None
        return f"{m // 60:02d}:{m % 60:02d}"

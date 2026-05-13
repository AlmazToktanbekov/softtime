import uuid

from sqlalchemy import Column, SmallInteger, Time, ForeignKey, Boolean, DateTime, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base

_DAY_NAMES = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]


class EmployeeSchedule(Base):
    __tablename__ = "employee_schedules"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    day_of_week = Column(SmallInteger, nullable=False)  # 0=Пн … 6=Вс
    is_working_day = Column(Boolean, default=True, nullable=False)
    start_time = Column(Time, nullable=True)   # null when is_working_day=False
    end_time = Column(Time, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user = relationship("User", back_populates="schedules")

    __table_args__ = (
        UniqueConstraint("user_id", "day_of_week", name="uq_schedule_user_day"),
    )

    @property
    def day_name(self) -> str:
        return _DAY_NAMES[self.day_of_week] if 0 <= self.day_of_week <= 6 else "?"

    @property
    def duration_minutes(self) -> int:
        """Work duration in minutes. 0 for non-working days or if times not set."""
        if not self.is_working_day or not self.start_time or not self.end_time:
            return 0
        start = self.start_time.hour * 60 + self.start_time.minute
        end = self.end_time.hour * 60 + self.end_time.minute
        return max(end - start, 0)

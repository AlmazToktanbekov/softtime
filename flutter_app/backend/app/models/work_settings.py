from sqlalchemy import Column, Integer, Boolean, DateTime
from sqlalchemy.sql import func
from app.database import Base


class WorkSettings(Base):
    __tablename__ = "work_settings"

    id = Column(Integer, primary_key=True, index=True)

    work_start_hour = Column(Integer, nullable=False, default=9)
    work_start_minute = Column(Integer, nullable=False, default=0)

    work_end_hour = Column(Integer, nullable=False, default=18)
    work_end_minute = Column(Integer, nullable=False, default=0)

    grace_period_minutes = Column(Integer, nullable=False, default=10)

    count_early_arrival = Column(Boolean, nullable=False, default=True)
    count_early_leave = Column(Boolean, nullable=False, default=True)
    count_overtime = Column(Boolean, nullable=False, default=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
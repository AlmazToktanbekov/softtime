from sqlalchemy import Column, Integer, String, Boolean, DateTime, Date, ForeignKey, Enum as SQLEnum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from datetime import datetime, time
from app.database import Base


class AttendanceStatus(str, enum.Enum):
    present = "present"
    late = "late"
    absent = "absent"
    incomplete = "incomplete"
    completed = "completed"
    manual = "manual"
    approved_absence = "approved_absence"  # Разрешение не прийти (с комментарием админа)


class Attendance(Base):
    __tablename__ = "attendance"

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False, index=True)
    date = Column(Date, nullable=False, index=True)
    check_in_time = Column(DateTime(timezone=True), nullable=True)
    check_out_time = Column(DateTime(timezone=True), nullable=True)
    status = Column(SQLEnum(AttendanceStatus), default=AttendanceStatus.absent)
    late_minutes = Column(Integer, default=0)
    check_in_ip = Column(String(45), nullable=True)
    check_out_ip = Column(String(45), nullable=True)
    qr_verified_in = Column(Boolean, default=False)
    qr_verified_out = Column(Boolean, default=False)
    office_network_id = Column(Integer, ForeignKey("office_networks.id"), nullable=True)
    note = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    employee = relationship("Employee", back_populates="attendances")
    office_network = relationship("OfficeNetwork")

    @property
    def employee_name(self):
        return self.employee.full_name if self.employee else None

    @property
    def formatted_check_in(self):
        if not self.check_in_time:
            return "--:--"
        return self.check_in_time.strftime("%H:%M")

    @property
    def formatted_check_out(self):
        if not self.check_out_time:
            return "--:--"
        return self.check_out_time.strftime("%H:%M")

    @property
    def work_minutes(self):
        if not self.check_in_time or not self.check_out_time:
            return 0
        delta = self.check_out_time - self.check_in_time
        return max(int(delta.total_seconds() // 60), 0)

    @property
    def work_duration(self):
        minutes = self.work_minutes
        if minutes <= 0:
            return None
        hours = minutes // 60
        mins = minutes % 60
        return f"{hours:02d}:{mins:02d}"

    def _get_work_settings(self):
        try:
            from app.models.work_settings import WorkSettings
            from app.database import SessionLocal

            db = SessionLocal()
            settings = db.query(WorkSettings).first()
            db.close()

            if settings:
                return settings
        except Exception:
            pass

        return None

    @property
    def early_arrival_minutes(self):
        if not self.check_in_time:
            return 0

        settings = self._get_work_settings()
        if not settings or not settings.count_early_arrival:
            return 0

        expected_dt = datetime.combine(
            self.date,
            time(settings.work_start_hour, settings.work_start_minute),
            tzinfo=self.check_in_time.tzinfo
        )
        diff = int((expected_dt - self.check_in_time).total_seconds() // 60)
        return max(diff, 0)

    @property
    def early_leave_minutes(self):
        if not self.check_out_time:
            return 0

        settings = self._get_work_settings()
        if not settings or not settings.count_early_leave:
            return 0

        expected_dt = datetime.combine(
            self.date,
            time(settings.work_end_hour, settings.work_end_minute),
            tzinfo=self.check_out_time.tzinfo
        )
        diff = int((expected_dt - self.check_out_time).total_seconds() // 60)
        return max(diff, 0)

    @property
    def overtime_minutes(self):
        if not self.check_out_time:
            return 0

        settings = self._get_work_settings()
        if not settings or not settings.count_overtime:
            return 0

        expected_dt = datetime.combine(
            self.date,
            time(settings.work_end_hour, settings.work_end_minute),
            tzinfo=self.check_out_time.tzinfo
        )
        diff = int((self.check_out_time - expected_dt).total_seconds() // 60)
        return max(diff, 0)

    @property
    def underwork_minutes(self):
        settings = self._get_work_settings()
        if not settings or not self.check_out_time:
            return 0

        expected_minutes = (
            (settings.work_end_hour * 60 + settings.work_end_minute)
            - (settings.work_start_hour * 60 + settings.work_start_minute)
        )
        return max(expected_minutes - self.work_minutes, 0)

    @property
    def is_late(self):
        return self.late_minutes > 0

    @property
    def came_early(self):
        return self.early_arrival_minutes > 0

    @property
    def left_early(self):
        return self.early_leave_minutes > 0

    @property
    def left_late(self):
        return self.overtime_minutes > 0
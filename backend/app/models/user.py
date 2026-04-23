import uuid
import enum

from sqlalchemy import Column, String, DateTime, Date, Text, ForeignKey, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class UserRole(str, enum.Enum):
    SUPER_ADMIN = "SUPER_ADMIN"
    ADMIN = "ADMIN"
    TEAM_LEAD = "TEAM_LEAD"
    EMPLOYEE = "EMPLOYEE"
    INTERN = "INTERN"


class UserStatus(str, enum.Enum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    LEAVE = "LEAVE"
    WARNING = "WARNING"
    BLOCKED = "BLOCKED"
    DELETED = "DELETED"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, nullable=False, index=True)
    phone = Column(String(60), unique=True, nullable=False)
    username = Column(String(100), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    role = Column(SQLEnum(UserRole), default=UserRole.EMPLOYEE, nullable=False)
    status = Column(SQLEnum(UserStatus), default=UserStatus.PENDING, nullable=False)

    team_name = Column(String(100), nullable=True)   # legacy / display only
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"), nullable=True, index=True)
    mentor_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    avatar_url = Column(String(500), nullable=True)
    fcm_token = Column(Text, nullable=True)
    hired_at = Column(Date, nullable=True)
    admin_comment = Column(Text, nullable=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # Self-referential: mentor → mentee (for interns)
    mentor = relationship(
        "User",
        foreign_keys=[mentor_id],
        remote_side="User.id",
        backref="mentees",
    )

    # Team membership
    team = relationship("Team", foreign_keys=[team_id], back_populates="members")

    # Relationships to other tables
    attendances = relationship(
        "Attendance", back_populates="user", foreign_keys="[Attendance.user_id]"
    )
    schedules = relationship(
        "EmployeeSchedule",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    duty_queue_entry = relationship(
        "DutyQueue", back_populates="user", uselist=False
    )
    duty_assignments = relationship(
        "DutyAssignment",
        back_populates="user",
        foreign_keys="[DutyAssignment.user_id]",
    )
    absence_requests = relationship(
        "AbsenceRequest",
        back_populates="user",
        foreign_keys="[AbsenceRequest.user_id]",
    )

    @property
    def is_active(self) -> bool:
        return self.status == UserStatus.ACTIVE

    @property
    def is_admin(self) -> bool:
        return self.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN)

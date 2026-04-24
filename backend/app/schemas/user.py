from datetime import date, datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, field_validator

from app.models.user import UserRole, UserStatus


# ── Create payload (Admin creates employee directly) ──────────────────────────

class UserCreate(BaseModel):
    full_name: str
    email: EmailStr
    phone: Optional[str] = None
    username: str
    password: str
    role: UserRole = UserRole.EMPLOYEE
    team_name: Optional[str] = None
    hired_at: Optional[date] = None


# ── Approve/Reject PENDING user ───────────────────────────────────────────────

class UserApproveRequest(BaseModel):
    role: UserRole = UserRole.EMPLOYEE
    mentor_id: Optional[UUID] = None
    comment: Optional[str] = None


class UserRejectRequest(BaseModel):
    reason: Optional[str] = None


# ── Shared base ───────────────────────────────────────────────────────────────

class UserBase(BaseModel):
    id: UUID
    full_name: str
    email: str
    phone: str
    username: str
    role: UserRole
    status: UserStatus
    team_name: Optional[str]
    team_id: Optional[UUID]
    avatar_url: Optional[str]
    hired_at: Optional[date]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── List item (compact) ───────────────────────────────────────────────────────

class UserListItem(UserBase):
    mentor_id: Optional[UUID]


# ── Detail (full profile) ─────────────────────────────────────────────────────

class UserDetail(UserBase):
    mentor_id: Optional[UUID]
    admin_comment: Optional[str]
    fcm_token: Optional[str]
    updated_at: Optional[datetime]


# ── Paginated response ────────────────────────────────────────────────────────

class PaginatedUsers(BaseModel):
    items: List[UserListItem]
    total: int
    page: int
    limit: int


# ── Update payload (PUT /users/{id}) ──────────────────────────────────────────

class UserUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    username: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    role: Optional[UserRole] = None
    team_name: Optional[str] = None
    team_id: Optional[UUID] = None
    mentor_id: Optional[UUID] = None
    hired_at: Optional[date] = None
    admin_comment: Optional[str] = None

    @field_validator("phone")
    @classmethod
    def phone_format(cls, v: Optional[str]) -> Optional[str]:
        import re
        if v is not None and not re.match(r"^\+\d{10,15}$", v):
            raise ValueError("Телефон в формате +996XXXXXXXXX")
        return v


# ── Status change (PATCH /users/{id}/status) ──────────────────────────────────

class UserStatusUpdateRequest(BaseModel):
    status: UserStatus
    comment: Optional[str] = None


# ── Avatar response ───────────────────────────────────────────────────────────

class AvatarResponse(BaseModel):
    avatar_url: str

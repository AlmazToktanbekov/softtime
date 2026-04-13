import re
from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, field_validator, model_validator

from app.models.user import UserRole, UserStatus

_PHONE_RE = re.compile(r"^\+\d{10,15}$")

# Roles a new user can self-select during registration
_ALLOWED_REGISTER_ROLES = {UserRole.EMPLOYEE, UserRole.INTERN, UserRole.TEAM_LEAD}


class RegisterRequest(BaseModel):
    full_name: str
    email: EmailStr
    # Accept phone with or without +996 prefix — Flutter sends digits only, we normalise here
    phone: str
    username: str
    password: str
    # Сотрудник | Стажёр | Ментор команды (TEAM_LEAD)
    role: UserRole = UserRole.EMPLOYEE
    # Обязателен для стажёра — активный ментор (TEAM_LEAD / ADMIN)
    mentor_id: Optional[UUID] = None

    @field_validator("full_name")
    @classmethod
    def full_name_not_empty(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2:
            raise ValueError("Имя должно содержать минимум 2 символа")
        return v

    @field_validator("username")
    @classmethod
    def username_valid(cls, v: str) -> str:
        v = v.strip()
        if not re.match(r"^[a-zA-Z0-9_]{3,30}$", v):
            raise ValueError("Логин: 3–30 символов, только латиница, цифры и _")
        return v

    @field_validator("phone")
    @classmethod
    def phone_valid(cls, v: str) -> str:
        v = v.strip()
        # If user sent digits only (e.g. "0700123456"), prepend +996
        if re.match(r"^\d{9,10}$", v):
            # 9 digits → +996XXXXXXXXX, 10 digits starting with 0 → +996XXXXXXXXX
            digits = v.lstrip("0") if v.startswith("0") else v
            v = f"+996{digits}"
        if not _PHONE_RE.match(v):
            raise ValueError("Телефон в формате +996XXXXXXXXX")
        return v

    @field_validator("role")
    @classmethod
    def role_allowed(cls, v: UserRole) -> UserRole:
        if v not in _ALLOWED_REGISTER_ROLES:
            raise ValueError("При регистрации можно выбрать только Сотрудник, Стажёр или Ментор команды")
        return v

    @model_validator(mode="after")
    def mentor_for_intern_only(self):
        if self.role == UserRole.INTERN:
            if self.mentor_id is None:
                raise ValueError("Укажите ментора из списка")
        elif self.mentor_id is not None:
            raise ValueError("Поле «ментор» доступно только для стажёра")
        return self

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        from app.utils.security import validate_password_strength
        validate_password_strength(v)
        return v


class LoginRequest(BaseModel):
    username: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


# ── Response models ───────────────────────────────────────────────────────────

class UserMeResponse(BaseModel):
    id: UUID
    full_name: str
    email: str
    phone: str
    username: str
    role: UserRole
    status: UserStatus
    team_name: Optional[str]
    team_id: Optional[UUID]
    mentor_id: Optional[UUID]
    avatar_url: Optional[str]
    hired_at: Optional[date]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserMeResponse

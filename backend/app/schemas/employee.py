from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import date, datetime


class EmployeeCreate(BaseModel):
    full_name: str
    email: EmailStr
    phone: Optional[str] = None
    department: Optional[str] = None
    position: Optional[str] = None
    hire_date: Optional[date] = None
    username: str
    password: str


class EmployeeUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    department: Optional[str] = None
    position: Optional[str] = None
    hire_date: Optional[date] = None


class EmployeeResponse(BaseModel):
    id: int
    full_name: str
    email: str
    phone: Optional[str]
    department: Optional[str]
    position: Optional[str]
    hire_date: Optional[date]
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True

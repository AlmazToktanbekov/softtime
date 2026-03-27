from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.database import get_db
from app.models.employee import Employee
from app.models.user import User, UserRole
from app.models.attendance import Attendance
from app.models.attendance_log import AttendanceLog
from app.schemas.employee import EmployeeCreate, EmployeeUpdate, EmployeeResponse
from app.utils.security import get_password_hash
from app.utils.dependencies import get_current_user, require_admin

router = APIRouter(prefix="/employees", tags=["Сотрудники"])


def _get_user_by_employee_id(employee_id: int, db: Session) -> Optional[User]:
    return db.query(User).filter(User.employee_id == employee_id).first()


def _archive_value(value: str, suffix: str) -> str:
    if not value:
        return value
    return f"{value}__archived__{suffix}"


@router.get("", response_model=List[EmployeeResponse])
def list_employees(
    skip: int = 0,
    limit: int = 100,
    department: str = None,
    include_inactive: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    query = db.query(Employee)

    if not include_inactive:
        query = query.filter(Employee.is_active == True)

    if department:
        query = query.filter(Employee.department == department)

    return query.offset(skip).limit(limit).all()


@router.post("", response_model=EmployeeResponse, status_code=status.HTTP_201_CREATED)
def create_employee(
    data: EmployeeCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    existing_employee_email = db.query(Employee).filter(Employee.email == data.email).first()
    if existing_employee_email:
        raise HTTPException(status_code=400, detail="Email уже используется")

    existing_user_username = db.query(User).filter(User.username == data.username).first()
    if existing_user_username:
        raise HTTPException(status_code=400, detail="Логин уже занят")

    existing_user_email = db.query(User).filter(User.email == data.email).first()
    if existing_user_email:
        raise HTTPException(status_code=400, detail="Email уже используется в users")

    employee = Employee(
        full_name=data.full_name,
        email=data.email,
        phone=data.phone,
        department=data.department,
        position=data.position,
        hire_date=data.hire_date,
        is_active=True,
    )
    db.add(employee)
    db.flush()

    user = User(
        username=data.username,
        email=data.email,
        password_hash=get_password_hash(data.password),
        role=UserRole.employee,
        employee_id=employee.id,
        is_active=True,
    )
    db.add(user)

    db.commit()
    db.refresh(employee)
    return employee


@router.get("/{employee_id}", response_model=EmployeeResponse)
def get_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role == UserRole.employee and current_user.employee_id != employee_id:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    return emp


@router.put("/{employee_id}", response_model=EmployeeResponse)
def update_employee(
    employee_id: int,
    data: EmployeeUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    old_email = emp.email
    payload = data.model_dump(exclude_none=True)

    if "email" in payload:
        duplicate_employee = db.query(Employee).filter(
            Employee.email == payload["email"],
            Employee.id != employee_id
        ).first()
        if duplicate_employee:
            raise HTTPException(status_code=400, detail="Email уже используется другим сотрудником")

        duplicate_user = db.query(User).filter(
            User.email == payload["email"],
            User.employee_id != employee_id
        ).first()
        if duplicate_user:
            raise HTTPException(status_code=400, detail="Email уже используется другим пользователем")

    for field, value in payload.items():
        setattr(emp, field, value)

    user = _get_user_by_employee_id(employee_id, db)
    if user and "email" in payload and user.email == old_email:
        user.email = payload["email"]

    db.commit()
    db.refresh(emp)
    return emp


@router.patch("/{employee_id}/deactivate")
def deactivate_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    if not emp.is_active:
        return {"message": "Сотрудник уже деактивирован"}

    emp.is_active = False

    user = _get_user_by_employee_id(employee_id, db)
    suffix = datetime.utcnow().strftime("%Y%m%d%H%M%S")

    if user:
        user.is_active = False
        user.username = _archive_value(user.username, suffix)
        user.email = _archive_value(user.email, suffix)

    emp.email = _archive_value(emp.email, suffix)

    db.commit()
    return {"message": "Сотрудник деактивирован и архивирован"}


@router.patch("/{employee_id}/activate")
def activate_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    emp.is_active = True

    user = _get_user_by_employee_id(employee_id, db)
    if user:
        user.is_active = True

    db.commit()
    return {"message": "Сотрудник активирован"}


@router.delete("/{employee_id}")
def delete_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    # Сначала удаляем всю связанную историю
    db.query(AttendanceLog).filter(AttendanceLog.employee_id == employee_id).delete(synchronize_session=False)
    db.query(Attendance).filter(Attendance.employee_id == employee_id).delete(synchronize_session=False)

    # Потом удаляем связанного user
    user = _get_user_by_employee_id(employee_id, db)
    if user:
        db.delete(user)

    # Потом самого сотрудника
    db.delete(emp)
    db.commit()

    return {"message": "Сотрудник полностью удалён"}

    # Если force=true — сначала удаляем связанную историю
    if force:
        db.query(AttendanceLog).filter(AttendanceLog.employee_id == employee_id).delete(synchronize_session=False)
        db.query(Attendance).filter(Attendance.employee_id == employee_id).delete(synchronize_session=False)

    user = _get_user_by_employee_id(employee_id, db)
    if user:
        db.delete(user)

    db.delete(emp)
    db.commit()

    if force:
        return {"message": "Сотрудник и вся связанная история полностью удалены"}

    return {"message": "Сотрудник полностью удалён"}
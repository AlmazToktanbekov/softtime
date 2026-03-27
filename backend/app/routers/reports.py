from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import date, timedelta
from app.database import get_db
from app.models.employee import Employee
from app.models.attendance import Attendance, AttendanceStatus
from app.models.user import User
from app.utils.dependencies import require_admin_or_manager

router = APIRouter(prefix="/reports", tags=["Отчеты"])


def build_attendance_summary(records: list, employees: list) -> dict:
    total = len(employees)

    employee_ids_with_record = {
        r.employee_id for r in records if r.check_in_time is not None
    }

    #
    # кто вообще был сегодня кто сейчас в офисе: пришёл, но ещё не отметил уход
    in_office_now = sum(
        1 for r in records
        if r.check_in_time is not None and r.check_out_time is None
    )

    # кто был сегодня хотя бы один раз
    worked_today = len(employee_ids_with_record)

    # кто завершил день
    completed = sum(
        1 for r in records
        if r.check_in_time is not None and r.check_out_time is not None
    )

    # кто пришёл, но день ещё не завершён
    incomplete = sum(
        1 for r in records
        if r.check_in_time is not None and r.check_out_time is None
    )

    # опоздавшие
    late = sum(1 for r in records if (r.late_minutes or 0) > 0)

    # отсутствующие = вообще не было check-in сегодня
    absent = max(total - worked_today, 0)

    attendance_rate = round((worked_today / total * 100) if total > 0 else 0, 1)

    return {
        "total_employees": total,
        "worked_today": worked_today,
        "in_office_now": in_office_now,
        "late": late,
        "absent": absent,
        "completed": completed,
        "incomplete": incomplete,
        "attendance_rate": attendance_rate,
    }


from datetime import datetime, time

@router.get("/daily")
def daily_report(
    report_date: date = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_manager)
):
    if not report_date:
        report_date = date.today()

    records = db.query(Attendance).filter(Attendance.date == report_date).all()
    employees = db.query(Employee).filter(Employee.is_active == True).all()

    # Автоматически помечаем незавершённые записи после конца дня
    now = datetime.now()
    day_is_over = report_date < date.today() or (
        report_date == date.today() and now.time() >= time(18, 0)
    )

    changed = False
    for r in records:
        if r.check_in_time is not None and r.check_out_time is None:
            if day_is_over and r.status in [AttendanceStatus.present, AttendanceStatus.late]:
                r.status = AttendanceStatus.incomplete
                changed = True

    if changed:
        db.commit()
        for r in records:
            db.refresh(r)

    summary = build_attendance_summary(records, employees)

    detail = []
    emp_map = {e.id: e for e in employees}

    for r in records:
        emp = emp_map.get(r.employee_id)
        detail.append({
            "id": r.id,
            "employee_id": r.employee_id,
            "employee_name": emp.full_name if emp else "Неизвестно",
            "full_name": emp.full_name if emp else "Неизвестно",
            "department": emp.department if emp else None,
            "check_in_time": r.formatted_check_in if hasattr(r, "formatted_check_in") else (r.check_in_time.strftime("%H:%M") if r.check_in_time else None),
            "check_out_time": r.formatted_check_out if hasattr(r, "formatted_check_out") else (r.check_out_time.strftime("%H:%M") if r.check_out_time else None),
            "formatted_check_in": r.formatted_check_in if hasattr(r, "formatted_check_in") else "--:--",
            "formatted_check_out": r.formatted_check_out if hasattr(r, "formatted_check_out") else "--:--",
            "status": r.status.value if hasattr(r.status, "value") else str(r.status),
            "late_minutes": getattr(r, "late_minutes", 0) or 0,
            "early_arrival_minutes": getattr(r, "early_arrival_minutes", 0) or 0,
            "early_leave_minutes": getattr(r, "early_leave_minutes", 0) or 0,
            "overtime_minutes": getattr(r, "overtime_minutes", 0) or 0,
            "work_duration": getattr(r, "work_duration", None),
            "note": getattr(r, "note", None),
        })

    return {"date": report_date, "summary": summary, "detail": detail}

@router.get("/weekly")
def weekly_report(
    week_start: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_manager)
):
    if not week_start:
        today = date.today()
        week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)

    records = db.query(Attendance).filter(
        Attendance.date >= week_start,
        Attendance.date <= week_end
    ).all()

    employees = db.query(Employee).filter(Employee.is_active == True).all()
    days_count = (week_end - week_start).days + 1

    daily = {}
    for i in range(days_count):
        d = week_start + timedelta(days=i)
        day_records = [r for r in records if r.date == d]
        daily[str(d)] = build_attendance_summary(day_records, employees)

    return {
        "week_start": week_start,
        "week_end": week_end,
        "days": daily,
        "total_records": len(records)
    }


@router.get("/monthly")
def monthly_report(
    year: int = Query(default=None),
    month: int = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_manager)
):
    today = date.today()
    if not year:
        year = today.year
    if not month:
        month = today.month

    month_start = date(year, month, 1)
    if month == 12:
        month_end = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        month_end = date(year, month + 1, 1) - timedelta(days=1)

    records = db.query(Attendance).filter(
        Attendance.date >= month_start,
        Attendance.date <= month_end
    ).all()

    employees = db.query(Employee).filter(Employee.is_active == True).all()

    emp_summary = []
    for emp in employees:
        emp_records = [r for r in records if r.employee_id == emp.id]

        days_present = sum(1 for r in emp_records if r.check_in_time is not None)
        days_late = sum(1 for r in emp_records if (r.late_minutes or 0) > 0)
        total_late_min = sum((r.late_minutes or 0) for r in emp_records)

        emp_summary.append({
            "employee_id": emp.id,
            "full_name": emp.full_name,
            "department": emp.department,
            "days_present": days_present,
            "days_late": days_late,
            "total_late_minutes": total_late_min
        })

    return {
        "year": year,
        "month": month,
        "period": f"{month_start} — {month_end}",
        "employees": emp_summary
    }


@router.get("/department")
def department_report(
    department: str,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_manager)
):
    if not start_date:
        start_date = date.today() - timedelta(days=30)
    if not end_date:
        end_date = date.today()

    employees = db.query(Employee).filter(
        Employee.department == department,
        Employee.is_active == True
    ).all()

    emp_ids = [e.id for e in employees]
    records = db.query(Attendance).filter(
        Attendance.employee_id.in_(emp_ids),
        Attendance.date >= start_date,
        Attendance.date <= end_date
    ).all()

    summary = build_attendance_summary(records, employees)
    return {
        "department": department,
        "period": {"start": start_date, "end": end_date},
        "summary": summary,
        "employees_count": len(employees)
    }
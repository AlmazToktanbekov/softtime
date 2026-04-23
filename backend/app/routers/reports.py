from datetime import date, datetime, time, timedelta
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.attendance import Attendance, AttendanceStatus
from app.models.user import User, UserRole, UserStatus
from app.utils.dependencies import require_admin_or_teamlead, get_current_user

router = APIRouter(prefix="/reports", tags=["Отчёты"])


def _fmt_time(dt) -> Optional[str]:
    """Format datetime to HH:MM in server local timezone."""
    if not dt:
        return None
    if dt.tzinfo is not None:
        return dt.astimezone().strftime("%H:%M")
    return dt.strftime("%H:%M")


# ─── helpers ─────────────────────────────────────────────────────────────────

def _build_summary(records: list, employees: list) -> dict:
    total = len(employees)
    user_ids_present = {r.user_id for r in records if r.check_in_time is not None}

    worked = len(user_ids_present)
    in_office = sum(1 for r in records if r.check_in_time and not r.check_out_time)
    late = sum(1 for r in records if (r.late_minutes or 0) > 0)
    absent = max(total - worked, 0)
    present = sum(1 for r in records if r.check_in_time and r.check_out_time)
    attendance_rate = round((worked / total * 100) if total > 0 else 0, 1)

    return {
        "total_employees": total,
        "present": present,
        "worked_today": worked,
        "in_office_now": in_office,
        "late": late,
        "absent": absent,
        "attendance_rate": attendance_rate,
    }


def _emp_detail(r: Attendance, emp_map: dict) -> dict:
    emp = emp_map.get(r.user_id)
    return {
        "id": str(r.id),
        "user_id": str(r.user_id),
        "employee_name": emp.full_name if emp else "Неизвестно",
        "team_name": getattr(emp, "team_name", None) if emp else None,
        "check_in_time": _fmt_time(r.check_in_time),
        "check_out_time": _fmt_time(r.check_out_time),
        "status": r.status.value if hasattr(r.status, "value") else str(r.status),
        "late_minutes": r.late_minutes or 0,
        "work_duration": r.work_duration,
        "note": r.note,
    }


# ─── Daily ───────────────────────────────────────────────────────────────────

@router.get("/daily")
def daily_report(
    report_date: Optional[date] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    if not report_date:
        report_date = date.today()

    emp_q = db.query(User).filter(
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
        User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
    )
    if current_user.role == UserRole.TEAM_LEAD and current_user.team_name:
        emp_q = emp_q.filter(User.team_name == current_user.team_name)
    employees = emp_q.all()
    emp_ids = {e.id for e in employees}
    records = db.query(Attendance).filter(
        Attendance.date == report_date,
        Attendance.user_id.in_(emp_ids),
    ).all()

    # Автоматически закрываем незавершённые записи прошлых дней
    now = datetime.now()
    day_is_over = report_date < date.today() or (
        report_date == date.today() and now.time() >= time(23, 0)
    )
    changed = False
    for r in records:
        if r.check_in_time and not r.check_out_time:
            if day_is_over and r.status in (AttendanceStatus.PRESENT, AttendanceStatus.LATE):
                r.status = AttendanceStatus.INCOMPLETE
                changed = True
    if changed:
        db.commit()
        for r in records:
            db.refresh(r)

    emp_map = {e.id: e for e in employees}
    summary = _build_summary(records, employees)
    detail = [_emp_detail(r, emp_map) for r in records]

    return {"date": str(report_date), "summary": summary, "detail": detail}


# ─── Weekly ──────────────────────────────────────────────────────────────────

@router.get("/weekly")
def weekly_report(
    week_start: Optional[date] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    if not week_start:
        today = date.today()
        week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)

    emp_q = db.query(User).filter(
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
        User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
    )
    if current_user.role == UserRole.TEAM_LEAD and current_user.team_name:
        emp_q = emp_q.filter(User.team_name == current_user.team_name)
    employees = emp_q.all()
    emp_ids = {e.id for e in employees}

    records = db.query(Attendance).filter(
        Attendance.date >= week_start,
        Attendance.date <= week_end,
        Attendance.user_id.in_(emp_ids),
    ).all()

    days_count = (week_end - week_start).days + 1
    daily = {}
    for i in range(days_count):
        d = week_start + timedelta(days=i)
        day_records = [r for r in records if r.date == d]
        daily[str(d)] = _build_summary(day_records, employees)

    return {
        "week_start": str(week_start),
        "week_end": str(week_end),
        "days": daily,
        "total_records": len(records),
    }


# ─── Monthly ─────────────────────────────────────────────────────────────────

@router.get("/monthly")
def monthly_report(
    year: Optional[int] = Query(default=None),
    month: Optional[int] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
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

    emp_q = db.query(User).filter(
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
        User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
    )
    if current_user.role == UserRole.TEAM_LEAD and current_user.team_name:
        emp_q = emp_q.filter(User.team_name == current_user.team_name)
    employees = emp_q.all()
    emp_ids = {e.id for e in employees}

    records = db.query(Attendance).filter(
        Attendance.date >= month_start,
        Attendance.date <= month_end,
        Attendance.user_id.in_(emp_ids),
    ).all()

    emp_summary = []
    for emp in employees:
        emp_records = [r for r in records if r.user_id == emp.id]
        days_present = sum(1 for r in emp_records if r.check_in_time)
        days_absent = sum(1 for r in emp_records if r.status == AttendanceStatus.ABSENT)
        days_late = sum(1 for r in emp_records if (r.late_minutes or 0) > 0)
        days_approved = sum(1 for r in emp_records if r.status == AttendanceStatus.APPROVED_ABSENCE)
        days_incomplete = sum(1 for r in emp_records if r.status == AttendanceStatus.INCOMPLETE)
        total_late_min = sum((r.late_minutes or 0) for r in emp_records)
        total_work_min = sum((r.work_minutes or 0) for r in emp_records if r.work_minutes)

        emp_summary.append({
            "user_id": str(emp.id),
            "full_name": emp.full_name,
            "team_name": getattr(emp, "team_name", None),
            "days_present": days_present,
            "days_absent": days_absent,
            "days_late": days_late,
            "days_approved_absence": days_approved,
            "days_incomplete": days_incomplete,
            "total_late_minutes": total_late_min,
            "total_work_minutes": total_work_min,
        })

    # Сортировка по присутствию (убывание)
    emp_summary.sort(key=lambda x: x["days_present"], reverse=True)

    summary = _build_summary(records, employees)

    return {
        "year": year,
        "month": month,
        "period": f"{month_start} — {month_end}",
        "summary": summary,
        "employees": emp_summary,
    }


# ─── Per-employee ─────────────────────────────────────────────────────────────

@router.get("/employee/{user_id}")
def employee_report(
    user_id: UUID,
    start_date: Optional[date] = Query(default=None),
    end_date: Optional[date] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Отчёт по конкретному сотруднику. Сотрудник видит только себя."""
    is_admin = current_user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN, UserRole.TEAM_LEAD)
    if not is_admin and str(current_user.id) != str(user_id):
        from fastapi import HTTPException
        raise HTTPException(status_code=403, detail="Доступ запрещён")

    # TeamLead видит только свою команду
    if current_user.role == UserRole.TEAM_LEAD and str(current_user.id) != str(user_id):
        target = db.query(User).filter(User.id == user_id).first()
        if target and target.team_name != current_user.team_name:
            from fastapi import HTTPException
            raise HTTPException(status_code=403, detail="Нет доступа к сотрудникам другой команды")

    if not start_date:
        today = date.today()
        start_date = date(today.year, today.month, 1)
    if not end_date:
        end_date = date.today()

    emp = db.query(User).filter(User.id == user_id).first()
    if not emp:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    records = db.query(Attendance).filter(
        Attendance.user_id == user_id,
        Attendance.date >= start_date,
        Attendance.date <= end_date,
    ).order_by(Attendance.date.desc()).all()

    days_present = sum(1 for r in records if r.check_in_time)
    days_late = sum(1 for r in records if (r.late_minutes or 0) > 0)
    total_late_min = sum((r.late_minutes or 0) for r in records)
    total_work_min = sum((r.work_minutes or 0) for r in records if r.work_minutes)

    detail = [
        {
            "date": str(r.date),
            "check_in": _fmt_time(r.check_in_time),
            "check_out": _fmt_time(r.check_out_time),
            "status": r.status.value if hasattr(r.status, "value") else str(r.status),
            "late_minutes": r.late_minutes or 0,
            "work_duration": r.work_duration,
            "note": r.note,
        }
        for r in records
    ]

    return {
        "user_id": str(user_id),
        "full_name": emp.full_name,
        "period": {"start": str(start_date), "end": str(end_date)},
        "stats": {
            "days_present": days_present,
            "days_late": days_late,
            "total_late_minutes": total_late_min,
            "total_work_minutes": total_work_min,
        },
        "records": detail,
    }


# ─── Period (arbitrary date range) ──────────────────────────────────────────

@router.get("/period")
def period_report(
    start_date: Optional[date] = Query(default=None),
    end_date: Optional[date] = Query(default=None),
    user_id: Optional[UUID] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """Отчёт за произвольный период: данные для графика + сводка по сотрудникам."""
    today = date.today()
    if not start_date:
        start_date = today - timedelta(days=6)
    if not end_date:
        end_date = today

    emp_q = db.query(User).filter(
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
        User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
    )
    if current_user.role == UserRole.TEAM_LEAD and current_user.team_name:
        emp_q = emp_q.filter(User.team_name == current_user.team_name)
    if user_id:
        emp_q = emp_q.filter(User.id == user_id)
    employees = emp_q.all()
    emp_ids = {e.id for e in employees}

    records = (
        db.query(Attendance).filter(
            Attendance.date >= start_date,
            Attendance.date <= end_date,
            Attendance.user_id.in_(emp_ids),
        ).all()
        if emp_ids else []
    )

    # Chart data — one entry per day
    total_days = (end_date - start_date).days + 1
    chart_data = []
    for i in range(total_days):
        d = start_date + timedelta(days=i)
        day_recs = [r for r in records if r.date == d]
        present = sum(1 for r in day_recs if r.check_in_time)
        absent = len(employees) - present
        late = sum(1 for r in day_recs if (r.late_minutes or 0) > 0)
        approved = sum(1 for r in day_recs if r.status == AttendanceStatus.APPROVED_ABSENCE)
        chart_data.append({
            "date": str(d),
            "present": present,
            "absent": max(absent, 0),
            "late": late,
            "approved_absence": approved,
        })

    # Per-employee summary
    emp_summary = []
    for emp in employees:
        emp_records = [r for r in records if r.user_id == emp.id]
        days_present = sum(1 for r in emp_records if r.check_in_time)
        days_absent = sum(1 for r in emp_records if r.status == AttendanceStatus.ABSENT)
        days_late = sum(1 for r in emp_records if (r.late_minutes or 0) > 0)
        days_approved = sum(1 for r in emp_records if r.status == AttendanceStatus.APPROVED_ABSENCE)
        total_late_min = sum((r.late_minutes or 0) for r in emp_records)
        total_work_min = sum((r.work_minutes or 0) for r in emp_records if r.work_minutes)
        emp_summary.append({
            "user_id": str(emp.id),
            "full_name": emp.full_name,
            "team_name": getattr(emp, "team_name", None),
            "days_present": days_present,
            "days_absent": days_absent,
            "days_late": days_late,
            "days_approved_absence": days_approved,
            "total_late_minutes": total_late_min,
            "total_work_minutes": total_work_min,
        })
    emp_summary.sort(key=lambda x: x["total_work_minutes"], reverse=True)

    return {
        "start_date": str(start_date),
        "end_date": str(end_date),
        "chart_data": chart_data,
        "employees": emp_summary,
        "summary": _build_summary(records, employees),
    }


# ─── Department ───────────────────────────────────────────────────────────────

@router.get("/department")
def department_report(
    department: str,
    start_date: Optional[date] = Query(default=None),
    end_date: Optional[date] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    if not start_date:
        start_date = date.today() - timedelta(days=30)
    if not end_date:
        end_date = date.today()

    employees = (
        db.query(User)
        .filter(
            User.team_name == department,
            User.status == UserStatus.ACTIVE,
            User.deleted_at.is_(None),
            User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        )
        .all()
    )

    emp_ids = [e.id for e in employees]
    records = db.query(Attendance).filter(
        Attendance.user_id.in_(emp_ids),
        Attendance.date >= start_date,
        Attendance.date <= end_date,
    ).all()

    summary = _build_summary(records, employees)
    return {
        "department": department,
        "period": {"start": str(start_date), "end": str(end_date)},
        "summary": summary,
        "employees_count": len(employees),
    }

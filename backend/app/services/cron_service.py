"""
Cron jobs для SoftTime.

Задача 23:00:
  1. Помечает все незакрытые сессии посещаемости как INCOMPLETE.
  2. Проверяет невыполненные дежурства и уведомляет Admin.
"""
from datetime import date
import logging

logger = logging.getLogger(__name__)


def mark_incomplete_sessions():
    """
    Для всех записей attendance за сегодня, где check_in есть, а check_out нет,
    и статус PRESENT или LATE — ставим INCOMPLETE.
    Уведомляем Admin о списке сотрудников, забывших check-out.
    """
    from app.database import SessionLocal
    from app.models.attendance import Attendance, AttendanceStatus
    from app.models.user import User, UserRole, UserStatus
    from app.utils.fcm import notify_users

    db = SessionLocal()
    try:
        today = date.today()
        records = (
            db.query(Attendance)
            .filter(
                Attendance.date == today,
                Attendance.check_in_time.isnot(None),
                Attendance.check_out_time.is_(None),
                Attendance.status.in_(
                    [AttendanceStatus.PRESENT, AttendanceStatus.LATE]
                ),
            )
            .all()
        )

        count = 0
        for r in records:
            r.status = AttendanceStatus.INCOMPLETE
            count += 1

        if count:
            db.commit()
            logger.info(f"[CRON 23:00] INCOMPLETE: помечено {count} записей за {today}")

            # Уведомить Admin о сотрудниках, забывших check-out
            admins = (
                db.query(User)
                .filter(
                    User.deleted_at.is_(None),
                    User.status == UserStatus.ACTIVE,
                    User.role.in_((UserRole.ADMIN, UserRole.SUPER_ADMIN)),
                    User.fcm_token.isnot(None),
                )
                .all()
            )
            notify_users(
                admins,
                title="Незакрытые сессии посещаемости",
                body=f"{count} сотрудник(а/ов) не сделали check-out за {today}",
                data={"type": "incomplete_sessions", "count": count, "date": str(today)},
            )
        else:
            logger.info(f"[CRON 23:00] Нет незакрытых сессий за {today}")
    except Exception as e:
        db.rollback()
        logger.error(f"[CRON 23:00] Ошибка посещаемости: {e}")
    finally:
        db.close()


def check_incomplete_duties():
    """
    Проверяет дежурства за сегодня, которые не подтверждены к 23:00.
    Уведомляет Admin.
    """
    from app.database import SessionLocal
    from app.models.duty import DutyAssignment
    from app.models.user import User, UserRole, UserStatus
    from app.utils.fcm import notify_users

    db = SessionLocal()
    try:
        today = date.today()
        unverified = (
            db.query(DutyAssignment)
            .filter(
                DutyAssignment.date == today,
                DutyAssignment.verified.is_(False),
            )
            .all()
        )

        if not unverified:
            logger.info(f"[CRON 23:00] Все дежурства за {today} подтверждены")
            return

        count = len(unverified)
        logger.warning(f"[CRON 23:00] Неподтверждённые дежурства: {count} за {today}")

        admins = (
            db.query(User)
            .filter(
                User.deleted_at.is_(None),
                User.status == UserStatus.ACTIVE,
                User.role.in_((UserRole.ADMIN, UserRole.SUPER_ADMIN)),
                User.fcm_token.isnot(None),
            )
            .all()
        )
        notify_users(
            admins,
            title="Дежурства не подтверждены",
            body=f"{count} дежурств(а) не выполнено или не подтверждено за {today}",
            data={"type": "duty_incomplete", "count": count, "date": str(today)},
        )
    except Exception as e:
        logger.error(f"[CRON 23:00] Ошибка проверки дежурств: {e}")
    finally:
        db.close()


def award_daily_attendance_points():
    """
    Каждый день в 18:30 начисляет 10 очков всем, кто сегодня был присутствующим или опоздал.
    """
    from app.database import SessionLocal
    from app.models.attendance import Attendance, AttendanceStatus
    from app.routers.extras import _add_points

    db = SessionLocal()
    try:
        today = date.today()
        present = db.query(Attendance).filter(
            Attendance.date == today,
            Attendance.status.in_([AttendanceStatus.PRESENT]),
        ).all()
        for a in present:
            _add_points(db, a.user_id, 10, f"Без опозданий {today}")
        db.commit()
        logger.info(f"[CRON 18:30] Начислено очков {len(present)} сотрудникам")
    except Exception as e:
        db.rollback()
        logger.error(f"[CRON 18:30] Ошибка начисления очков: {e}")
    finally:
        db.close()


def notify_mentors_about_late_interns():
    """
    В 10:00 проверяем кто из стажеров не отметился, уведомляем их менторов.
    """
    from app.database import SessionLocal
    from app.models.attendance import Attendance
    from app.models.user import User, UserRole, UserStatus
    from app.utils.fcm import notify_user

    db = SessionLocal()
    try:
        today = date.today()
        interns = db.query(User).filter(
            User.role == UserRole.INTERN,
            User.status == UserStatus.ACTIVE,
            User.deleted_at.is_(None),
            User.mentor_id.isnot(None),
        ).all()

        for intern in interns:
            checked_in = db.query(Attendance).filter(
                Attendance.user_id == intern.id,
                Attendance.date == today,
            ).first()
            if not checked_in and intern.mentor_id:
                mentor = db.query(User).filter(User.id == intern.mentor_id).first()
                if mentor:
                    notify_user(
                        mentor,
                        title="⚠️ Стажер не явился",
                        body=f"{intern.full_name} ещё не отметился сегодня",
                        data={"type": "intern_absent", "intern_id": str(intern.id)},
                    )
        logger.info(f"[CRON 10:00] Проверены стажеры")
    except Exception as e:
        logger.error(f"[CRON 10:00] Ошибка уведомлений менторов: {e}")
    finally:
        db.close()


def setup_scheduler():
    """Создаёт и возвращает настроенный APScheduler."""
    from apscheduler.schedulers.background import BackgroundScheduler

    scheduler = BackgroundScheduler(timezone="Asia/Bishkek")
    scheduler.add_job(
        mark_incomplete_sessions,
        trigger="cron",
        hour=23,
        minute=0,
        id="incomplete_23",
        replace_existing=True,
    )
    scheduler.add_job(
        check_incomplete_duties,
        trigger="cron",
        hour=23,
        minute=5,
        id="duty_check_23",
        replace_existing=True,
    )
    scheduler.add_job(
        award_daily_attendance_points,
        trigger="cron",
        hour=18,
        minute=30,
        id="award_points_18_30",
        replace_existing=True,
    )
    scheduler.add_job(
        notify_mentors_about_late_interns,
        trigger="cron",
        hour=10,
        minute=0,
        id="mentor_notify_10",
        replace_existing=True,
    )
    return scheduler


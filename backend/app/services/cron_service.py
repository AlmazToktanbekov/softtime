"""
Cron jobs для SoftTime.

Задача 23:00 — помечает все незакрытые сессии посещаемости как INCOMPLETE.
Запускается один раз в сутки в 23:00 по местному времени.
"""
from datetime import date, datetime
import logging

logger = logging.getLogger(__name__)


def mark_incomplete_sessions():
    """
    Для всех записей attendance за сегодня, где check_in есть, а check_out нет,
    и статус PRESENT или LATE — ставим INCOMPLETE.
    """
    from app.database import SessionLocal
    from app.models.attendance import Attendance, AttendanceStatus

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
        else:
            logger.info(f"[CRON 23:00] Нет незакрытых сессий за {today}")
    except Exception as e:
        db.rollback()
        logger.error(f"[CRON 23:00] Ошибка: {e}")
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
    return scheduler

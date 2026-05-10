"""
Notification service for sending push notifications and tracking.
"""
from datetime import datetime, timezone
import logging
from typing import List, Optional
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.user import User, UserRole, UserStatus
from app.utils.fcm import notify_user, notify_users

logger = logging.getLogger(__name__)


def notify_new_employee_pending(db: Session, employee: User) -> int:
    """
    Notify all admins about new employee waiting for approval.
    """
    admins = db.query(User).filter(
        User.role.in_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
    ).all()

    if not admins:
        logger.warning("No active admins to notify")
        return 0

    title = "Новый сотрудник на подтверждение"
    body = f"{employee.full_name} ждет подтверждения"
    data = {"action": "employee_pending", "employee_id": str(employee.id)}

    return notify_users(admins, title, body, data)


def notify_employee_approved(db: Session, employee: User) -> bool:
    """
    Notify employee that their account was approved.
    """
    if not employee or not employee.fcm_token:
        return False

    title = "Учётная запись одобрена"
    body = "Ваша учётная запись была подтверждена администратором"
    data = {"action": "employee_approved"}

    return notify_user(employee, title, body, data)


def notify_employee_rejected(db: Session, employee: User, reason: Optional[str]) -> bool:
    """
    Notify employee that their account was rejected.
    """
    if not employee or not employee.fcm_token:
        return False

    title = "Учётная запись отклонена"
    body = reason or "Ваша заявка была отклонена администратором"
    data = {"action": "employee_rejected"}

    return notify_user(employee, title, body, data)


def notify_duty_today(db: Session, employee: User) -> bool:
    """
    Notify employee that they are on duty today.
    """
    if not employee or not employee.fcm_token:
        return False

    title = "Сегодня ваше дежурство"
    body = "Не забудьте выполнить все задачи и отметить выполнение"
    data = {"action": "duty_today", "user_id": str(employee.id)}

    return notify_user(employee, title, body, data)


def notify_duty_incomplete(db: Session) -> int:
    """
    Notify admins about incomplete duties.
    """
    from app.models.duty import DutyAssignment, DutyStatus
    from datetime import date

    admins = db.query(User).filter(
        User.role.in_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
    ).all()

    if not admins:
        return 0

    incomplete_duties = db.query(DutyAssignment).filter(
        DutyAssignment.date == date.today(),
        DutyAssignment.verified == False,
    ).all()

    if not incomplete_duties:
        return 0

    names = [d.assigned_to.full_name for d in incomplete_duties if d.assigned_to]
    body = f"Не выполнены дежурства: {', '.join(names[:3])}"

    title = "Незавершённые дежурства"
    data = {"action": "duty_incomplete"}

    return notify_users(admins, title, body, data)


def notify_duty_swap_request(db: Session, from_user: User, to_user: User) -> bool:
    """
    Notify employee about incoming duty swap request.
    """
    if not to_user or not to_user.fcm_token:
        return False

    title = "Запрос на обмен дежурством"
    body = f"{from_user.full_name} предлагает обменяться дежурством"
    data = {"action": "duty_swap_request", "from_user_id": str(from_user.id)}

    return notify_user(to_user, title, body, data)


def notify_duty_swap_result(db: Session, user: User, accepted: bool, from_user: User) -> bool:
    """
    Notify employee about duty swap request result.
    """
    if not user or not user.fcm_token:
        return False

    if accepted:
        title = "Обмен дежурством принят"
        body = f"{from_user.full_name} согласился на обмен"
    else:
        title = "Обмен дежурством отклонён"
        body = f"{from_user.full_name} отклонил обмен"

    data = {"action": "duty_swap_result", "accepted": str(accepted)}

    return notify_user(user, title, body, data)


def notify_absence_request_result(db: Session, employee: User, approved: bool, comment: Optional[str]) -> bool:
    """
    Notify employee about absence request approval/rejection.
    """
    if not employee or not employee.fcm_token:
        return False

    if approved:
        title = "Заявка на отпуск одобрена"
        body = "Ваша заявка на отпуск была одобрена"
    else:
        title = "Заявка на отпуск отклонена"
        body = comment or "Ваша заявка на отпуск была отклонена"

    data = {"action": "absence_request_result", "approved": str(approved)}

    return notify_user(employee, title, body, data)


def notify_absence_request_new(db: Session, employee: User) -> int:
    """
    Notify admins about new absence request.
    """
    admins = db.query(User).filter(
        User.role.in_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
    ).all()

    if not admins:
        return 0

    title = "Новая заявка на отсутствие"
    body = f"Сотрудник {employee.full_name} подал заявку"
    data = {"action": "absence_request_new", "employee_id": str(employee.id)}

    return notify_users(admins, title, body, data)


def notify_news_published(db: Session, title_text: str, body_text: str) -> int:
    """
    Notify all active employees about new news.
    """
    employees = db.query(User).filter(
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
    ).all()

    if not employees:
        return 0

    data = {"action": "news_published"}

    return notify_users(employees, title_text, body_text, data)

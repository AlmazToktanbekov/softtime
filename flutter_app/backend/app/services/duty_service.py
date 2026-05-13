from datetime import date, datetime, timedelta, timezone
from typing import List, Optional
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.duty import DutyQueue, DutyAssignment, DutySwap, DutyChecklistItem, DutyType
from app.models.user import User, UserStatus


def _get_queue_order(db: Session, user_id: UUID) -> Optional[int]:
    entry = db.query(DutyQueue).filter(DutyQueue.user_id == user_id).first()
    return entry.queue_order if entry else None


def get_current_duty_user(
    db: Session,
    target_date: Optional[date] = None,
    duty_type: DutyType = DutyType.LUNCH,
) -> Optional[User]:
    """Пользователь на дежурстве (обед) в указанную дату."""
    if target_date is None:
        target_date = date.today()
    assignment = db.query(DutyAssignment).filter(
        DutyAssignment.date == target_date,
        DutyAssignment.duty_type == duty_type,
    ).first()
    if not assignment:
        return None
    return db.query(User).filter(User.id == assignment.user_id).first()


def reset_duty_assignment_progress(assignment: DutyAssignment) -> None:
    """Сброс отметок выполнения (новый ответственный или переназначение слота)."""
    assignment.is_completed = False
    assignment.completion_tasks = None
    assignment.completion_qr_verified = False
    assignment.completed_at = None
    assignment.verified = False
    assignment.verified_by = None
    assignment.verified_at = None
    assignment.admin_note = None


def submit_duty_completion(
    assignment: DutyAssignment,
    task_ids: List[UUID],
    db: Session,
) -> DutyAssignment:
    valid_items = (
        db.query(DutyChecklistItem)
        .filter(
            DutyChecklistItem.id.in_(task_ids),
            DutyChecklistItem.is_active == True,  # noqa: E712
        )
        .all()
    )
    if len(valid_items) != len(task_ids):
        raise ValueError("Один или несколько пунктов чек-листа недействительны")

    assignment.is_completed = True
    assignment.completion_tasks = [str(t) for t in task_ids]
    assignment.completion_qr_verified = True
    assignment.completed_at = datetime.now(timezone.utc)
    assignment.verified = False

    db.commit()
    db.refresh(assignment)
    return assignment


def verify_duty_completion(
    assignment: DutyAssignment,
    approve: bool,
    admin_note: Optional[str],
    admin_user_id: UUID,
    db: Session,
) -> DutyAssignment:
    assignment.verified = approve
    assignment.verified_by = admin_user_id
    assignment.verified_at = datetime.now(timezone.utc)
    if admin_note is not None:
        assignment.admin_note = admin_note

    if not approve:
        assignment.is_completed = False
    else:
        assignment.is_completed = True

    db.commit()
    db.refresh(assignment)
    return assignment


def generate_duty_assignments(db: Session, start_date: date, days: int) -> int:
    queue_entries = db.query(DutyQueue).order_by(DutyQueue.queue_order).all()
    if not queue_entries:
        raise ValueError("Очередь дежурств пуста. Настройте очередь в админ-панели.")

    user_ids = [q.user_id for q in queue_entries]
    n = len(user_ids)

    count_created = 0
    current_index = 0

    for i in range(days):
        current_date = start_date + timedelta(days=i)

        existing = db.query(DutyAssignment).filter(
            DutyAssignment.date == current_date,
            DutyAssignment.duty_type == DutyType.LUNCH,
        ).first()
        if existing:
            continue

        uid = user_ids[current_index]
        current_index = (current_index + 1) % n

        u = db.query(User).filter(User.id == uid, User.deleted_at.is_(None)).first()
        if not u or u.status != UserStatus.ACTIVE:
            continue

        assignment = DutyAssignment(user_id=uid, date=current_date, duty_type=DutyType.LUNCH)
        db.add(assignment)
        count_created += 1

    db.commit()
    return count_created


def update_queue_order(db: Session, ordered_user_ids: List[UUID]) -> None:
    db.query(DutyQueue).delete(synchronize_session=False)
    for order, uid in enumerate(ordered_user_ids):
        entry = DutyQueue(user_id=uid, queue_order=order)
        db.add(entry)
    db.commit()

from datetime import date, datetime, timezone
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.models.duty import DutyQueue, DutyAssignment, DutyChecklistItem, DutySwap, DutyType
from app.schemas.duty import (
    DutyQueueResponse,
    DutyAssignmentCreate,
    DutyAssignmentResponse,
    DutyCompletionSubmit,
    DutyVerifyRequest,
    DutySwapCreate,
    DutySwapResponse,
    DutyChecklistItemCreate,
    DutyChecklistItemUpdate,
    DutyChecklistItemResponse,
    WeeklyLunchScheduleRequest,
    DutyOverviewEntry,
)
from app.utils.dependencies import get_current_user, require_admin, require_admin_or_teamlead
from app.utils.audit import write_audit
from app.utils.fcm import notify_user, notify_users
from app.services.qr_service import validate_qr_token
from app.services.ip_service import get_client_ip, validate_office_network
from app.services.duty_service import (
    submit_duty_completion,
    verify_duty_completion,
    generate_duty_assignments,
    reset_duty_assignment_progress,
)

router = APIRouter(prefix="/duty", tags=["Дежурство"])


class ReorderQueueBody(BaseModel):
    user_ids: List[UUID]


# ============ Duty Queue Management ============


@router.get("/queue", response_model=List[DutyQueueResponse])
def list_duty_queue(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """Просмотр очереди дежурств."""
    return db.query(DutyQueue).order_by(DutyQueue.queue_order).all()


@router.post("/queue/reorder")
def reorder_queue(
    body: ReorderQueueBody,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Переупорядочить очередь."""
    users = (
        db.query(User)
        .filter(
            User.id.in_(body.user_ids),
            User.deleted_at.is_(None),
            User.status == UserStatus.ACTIVE,
            User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        )
        .all()
    )
    if len(users) != len(body.user_ids):
        raise HTTPException(status_code=400, detail="Не все пользователи найдены или неактивны")

    db.query(DutyQueue).delete(synchronize_session=False)
    for order, uid in enumerate(body.user_ids):
        db.add(DutyQueue(user_id=uid, queue_order=order))

    db.commit()
    return {"message": "Очередь обновлена", "count": len(body.user_ids)}


@router.post("/queue/generate")
def generate_assignations(
    start_date: date = Query(..., description="Начальная дата для генерации"),
    days: int = Query(30, description="Количество дней для планирования"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Автоматически создать назначения обеда на период из очереди."""
    try:
        count = generate_duty_assignments(db, start_date, days)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    return {"message": f"Создано {count} назначений", "count": count}


# ============ Today / Overview ============


@router.get("/today", response_model=List[DutyAssignmentResponse])
def get_today_duty(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Дежурные сегодня (оба типа). Для главного экрана."""
    today = date.today()
    assignments = db.query(DutyAssignment).filter(DutyAssignment.date == today).all()

    # For CLEANING — also check if this week's cleaning assignment falls today
    # (cleaning assignment date = Monday of the week, but completion is any day)
    from datetime import timedelta
    week_start = today - timedelta(days=today.weekday())
    cleaning_this_week = (
        db.query(DutyAssignment)
        .filter(
            DutyAssignment.duty_type == DutyType.CLEANING,
            DutyAssignment.date == week_start,
        )
        .first()
    )

    result = list(assignments)

    # Add cleaning assignment if not already included
    if cleaning_this_week and cleaning_this_week not in result:
        result.append(cleaning_this_week)

    return result


@router.get("/schedule", response_model=List[DutyAssignmentResponse])
def get_duty_schedule(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    duty_type: Optional[DutyType] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Расписание дежурств. Admin/TeamLead видят всех, остальные — только себя.
    Фильтр по типу: ?duty_type=LUNCH или ?duty_type=CLEANING
    """
    query = db.query(DutyAssignment)

    if duty_type:
        query = query.filter(DutyAssignment.duty_type == duty_type)
    if start_date:
        query = query.filter(DutyAssignment.date >= start_date)
    if end_date:
        query = query.filter(DutyAssignment.date <= end_date)

    if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN, UserRole.TEAM_LEAD):
        query = query.filter(DutyAssignment.user_id == current_user.id)

    return query.order_by(DutyAssignment.date).all()


@router.get("/overview", response_model=List[DutyOverviewEntry])
def get_duty_overview(
    start_date: date = Query(...),
    end_date: date = Query(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """
    Обзор дежурств для Admin-панели: кто и когда дежурит (оба типа).
    """
    assignments = (
        db.query(DutyAssignment)
        .filter(DutyAssignment.date >= start_date, DutyAssignment.date <= end_date)
        .order_by(DutyAssignment.date, DutyAssignment.duty_type)
        .all()
    )

    return [
        DutyOverviewEntry(
            date=a.date,
            duty_type=a.duty_type,
            user_id=a.user_id,
            user_full_name=a.user.full_name if a.user else None,
            is_completed=a.is_completed,
            verified=a.verified,
        )
        for a in assignments
    ]


# ============ Duty Statistics ============


@router.get("/stats", response_model=List[dict])
def get_duty_stats(
    start_date: date = Query(default=None),
    end_date: date = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """
    Статистика дежурств: сколько раз каждый сотрудник дежурил.
    """
    from datetime import date as date_cls
    from sqlalchemy import func

    today = date_cls.today()
    if not start_date:
        start_date = today - timedelta(days=90)
    if not end_date:
        end_date = today + timedelta(days=30)

    results = (
        db.query(
            User.id,
            User.full_name,
            func.count(DutyAssignment.id).label("total"),
            func.sum(func.cast(DutyAssignment.is_completed, int)).label("completed"),
            func.sum(func.cast(DutyAssignment.verified, int)).label("verified"),
        )
        .join(DutyAssignment, User.id == DutyAssignment.user_id)
        .filter(DutyAssignment.date >= start_date, DutyAssignment.date <= end_date)
        .group_by(User.id, User.full_name)
        .order_by(func.count(DutyAssignment.id).desc())
        .all()
    )

    return [
        {
            "user_id": str(r.id),
            "full_name": r.full_name,
            "total": r.total,
            "completed": r.completed or 0,
            "verified": r.verified or 0,
            "missed": r.total - (r.completed or 0),
        }
        for r in results
    ]


# ============ Duty Assignments (Admin) ============


def _user_can_be_assigned_duty(u: Optional[User]) -> bool:
    if not u or u.deleted_at is not None:
        return False
    return u.status in (UserStatus.ACTIVE, UserStatus.WARNING)


@router.post("/assign", response_model=DutyAssignmentResponse, status_code=201)
def assign_duty(
    data: DutyAssignmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """
    Назначить дежурного на дату. Тип передаётся в поле duty_type.
    - LUNCH: конкретный день (уникален по date+LUNCH)
    - CLEANING: дата = понедельник недели (уникален по date+CLEANING)
    Если на эту дату и тип уже есть назначение — переназначаем ответственного (удобно для админки).
    """
    u = db.query(User).filter(User.id == data.user_id, User.deleted_at.is_(None)).first()
    if not _user_can_be_assigned_duty(u):
        raise HTTPException(status_code=404, detail="Пользователь не найден или неактивен")

    existing = (
        db.query(DutyAssignment)
        .filter(DutyAssignment.date == data.date, DutyAssignment.duty_type == data.duty_type)
        .first()
    )

    if existing:
        old_uid = str(existing.user_id)
        if existing.user_id != data.user_id:
            reset_duty_assignment_progress(existing)
        existing.user_id = data.user_id
        db.commit()
        db.refresh(existing)
        write_audit(
            db,
            actor_id=current_user.id,
            action="REASSIGN_DUTY",
            entity="DutyAssignment",
            entity_id=existing.id,
            old_value={
                "user_id": old_uid,
                "date": str(data.date),
                "duty_type": data.duty_type.value,
            },
            new_value={
                "user_id": str(data.user_id),
                "date": str(data.date),
                "duty_type": data.duty_type.value,
            },
        )
        return existing

    assignment = DutyAssignment(
        user_id=data.user_id,
        date=data.date,
        duty_type=data.duty_type,
    )
    db.add(assignment)
    db.commit()
    db.refresh(assignment)
    write_audit(
        db,
        actor_id=current_user.id,
        action="ASSIGN_DUTY",
        entity="DutyAssignment",
        entity_id=assignment.id,
        new_value={
            "user_id": str(data.user_id),
            "date": str(data.date),
            "duty_type": data.duty_type.value,
        },
    )

    # Push notification → дежурному
    duty_label = "обеда" if data.duty_type.value == "LUNCH" else "уборки"
    notify_user(
        u,
        title="Вы назначены дежурным",
        body=f"Вы дежурите {data.date} ({duty_label})",
        data={"type": "duty_assigned", "assignment_id": str(assignment.id)},
    )

    return assignment


@router.post("/assign/weekly-lunch", response_model=List[DutyAssignmentResponse], status_code=201)
def assign_weekly_lunch(
    data: WeeklyLunchScheduleRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """
    Назначить обед на всю неделю (7 дней). Admin передаёт week_start (понедельник)
    и список {weekday, user_id} для каждого дня (0=пн … 6=вс).
    Существующие назначения на эти дни удаляются и создаются заново.
    """
    from datetime import timedelta

    week_monday = data.week_start - timedelta(days=data.week_start.weekday())

    # Delete existing LUNCH assignments for that week
    week_days = [week_monday + timedelta(days=i) for i in range(7)]
    db.query(DutyAssignment).filter(
        DutyAssignment.duty_type == DutyType.LUNCH,
        DutyAssignment.date.in_(week_days),
    ).delete(synchronize_session=False)

    created = []
    for entry in data.entries:
        if entry.user_id is None:
            continue
        target_date = week_monday + timedelta(days=entry.weekday)
        a = DutyAssignment(
            user_id=entry.user_id,
            date=target_date,
            duty_type=DutyType.LUNCH,
        )
        db.add(a)
        created.append(a)

    db.commit()
    for a in created:
        db.refresh(a)

    write_audit(
        db,
        actor_id=current_user.id,
        action="ASSIGN_WEEKLY_LUNCH",
        entity="DutyAssignment",
        entity_id=None,
        new_value={"week_start": str(week_monday), "count": len(created)},
    )
    return created


@router.delete("/assign/{assignment_id}", status_code=200)
def delete_assignment(
    assignment_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """Удалить назначение дежурства. Только Admin."""
    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")
    db.delete(assignment)
    db.commit()
    return {"message": "Назначение удалено"}


@router.patch("/assign/{assignment_id}/move", response_model=DutyAssignmentResponse)
def move_duty(
    assignment_id: UUID,
    data: DutyAssignmentMoveRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """
    Перенести дежурство на другую дату.
    """
    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")

    old_date = assignment.date
    old_user_id = assignment.user_id

    # Check if target date already has assignment of same type
    existing = db.query(DutyAssignment).filter(
        DutyAssignment.date == data.new_date,
        DutyAssignment.duty_type == assignment.duty_type,
    ).first()

    if existing:
        # Swap users
        existing.user_id = old_user_id
        existing.date = old_date

    assignment.date = data.new_date

    if data.new_user_id:
        assignment.user_id = data.new_user_id

    db.commit()
    db.refresh(assignment)

    write_audit(
        db,
        actor_id=current_user.id,
        action="MOVE_DUTY",
        entity="DutyAssignment",
        entity_id=assignment.id,
        old_value={"date": str(old_date), "user_id": str(old_user_id)},
        new_value={"date": str(data.new_date), "user_id": str(assignment.user_id)},
    )

    return assignment


# ============ My Duties ============


@router.get("/my", response_model=List[DutyAssignmentResponse])
def get_my_duty_assignments(
    duty_type: Optional[DutyType] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Мои дежурства (текущие и будущие). Опциональный фильтр по типу."""
    today = date.today()
    q = db.query(DutyAssignment).filter(
        DutyAssignment.user_id == current_user.id,
        DutyAssignment.date >= today,
    )
    if duty_type:
        q = q.filter(DutyAssignment.duty_type == duty_type)
    return q.order_by(DutyAssignment.date).all()


# ============ Complete & Verify ============


@router.patch("/{assignment_id}/complete", response_model=DutyAssignmentResponse)
def complete_duty(
    assignment_id: UUID,
    data: DutyCompletionSubmit,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Сотрудник отмечает выполнение дежурства (чек-лист + QR + офисная сеть)."""
    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")

    if assignment.user_id != current_user.id and current_user.role not in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
    ):
        raise HTTPException(status_code=403, detail="Вы не ответственны за это дежурство")

    # Проверка офисной сети (только для сотрудников, не для админов)
    if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        ip_address = get_client_ip(request)
        network_valid, _ = validate_office_network(ip_address, db)
        if not network_valid:
            raise HTTPException(
                status_code=403,
                detail="Подтверждение дежурства возможно только из офисной сети",
            )

    qr_valid, qr_msg = validate_qr_token(data.qr_token, db, expected_type="duty")
    if not qr_valid:
        raise HTTPException(status_code=400, detail=qr_msg)

    try:
        result = submit_duty_completion(assignment, data.tasks, db)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    # Push notification → Admin и Super Admin
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
        title="Дежурство выполнено — подтвердите",
        body=f"{current_user.full_name} отметил(а) завершение дежурства",
        data={"type": "duty_completed", "assignment_id": str(assignment_id)},
    )

    return result


@router.patch("/{assignment_id}/complete-manual", response_model=DutyAssignmentResponse)
def complete_duty_manual(
    assignment_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Admin вручную отмечает дежурство как выполненное (забыл скан QR)."""
    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")

    assignment.is_completed = True
    assignment.completion_qr_verified = False  # manual — QR не сканировался
    assignment.verified = True
    assignment.verified_by = current_user.id
    assignment.verified_at = datetime.now(timezone.utc)
    assignment.completed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(assignment)

    write_audit(
        db,
        actor_id=current_user.id,
        action="COMPLETE_DUTY_MANUAL",
        entity="DutyAssignment",
        entity_id=assignment.id,
        new_value={"manual": True},
    )
    return assignment


@router.patch("/{assignment_id}/verify", response_model=DutyAssignmentResponse)
def verify_duty(
    assignment_id: UUID,
    data: DutyVerifyRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    """Админ подтверждает или отклоняет выполненное дежурство."""
    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")

    return verify_duty_completion(
        assignment, data.approve, data.admin_note, current_user.id, db
    )


# ============ Checklist Management ============


@router.get("/checklist", response_model=List[DutyChecklistItemResponse])
def list_checklist(
    duty_type: Optional[DutyType] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Чеклист дежурного.
    Без фильтра — все активные пункты.
    С ?duty_type=LUNCH|CLEANING — пункты для конкретного типа + общие (duty_type=None).
    """
    q = db.query(DutyChecklistItem).filter(DutyChecklistItem.is_active == True)

    if duty_type:
        q = q.filter(
            (DutyChecklistItem.duty_type == duty_type)
            | (DutyChecklistItem.duty_type.is_(None))
        )

    return q.order_by(DutyChecklistItem.order).all()


@router.post("/checklist", response_model=DutyChecklistItemResponse, status_code=201)
def create_checklist_item(
    data: DutyChecklistItemCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    item = DutyChecklistItem(text=data.text, order=data.order, duty_type=data.duty_type)
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.patch("/checklist/{item_id}", response_model=DutyChecklistItemResponse)
def update_checklist_item(
    item_id: UUID,
    data: DutyChecklistItemUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    item = db.query(DutyChecklistItem).filter(DutyChecklistItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Элемент не найден")
    old_val = {"text": item.text, "order": item.order, "is_active": item.is_active, "duty_type": item.duty_type}
    if data.text is not None:
        item.text = data.text
    if data.order is not None:
        item.order = data.order
    if data.is_active is not None:
        item.is_active = data.is_active
    if data.duty_type is not None:
        item.duty_type = data.duty_type
    db.commit()
    db.refresh(item)
    write_audit(
        db,
        actor_id=current_user.id,
        action="UPDATE_CHECKLIST_ITEM",
        entity="DutyChecklistItem",
        entity_id=item.id,
        old_value=old_val,
        new_value={"text": item.text, "order": item.order, "is_active": item.is_active},
    )
    return item


@router.delete("/checklist/{item_id}")
def delete_checklist_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    item = db.query(DutyChecklistItem).filter(DutyChecklistItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Элемент не найден")
    db.delete(item)
    db.commit()
    return {"message": "Элемент удалён"}


# ============ Duty Swaps ============


class ColleagueItem(BaseModel):
    id: str
    full_name: str
    role: str

    class Config:
        from_attributes = True


@router.get("/colleagues", response_model=List[ColleagueItem])
def list_colleagues(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Список активных сотрудников для выбора при запросе обмена дежурством."""
    rows = (
        db.query(User)
        .filter(
            User.id != current_user.id,
            User.status == UserStatus.ACTIVE,
            User.deleted_at.is_(None),
            User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        )
        .order_by(User.full_name)
        .all()
    )
    return [ColleagueItem(id=str(r.id), full_name=r.full_name, role=r.role.value) for r in rows]


@router.get("/peer/{user_id}/assignments", response_model=List[DutyAssignmentResponse])
def peer_assignments_for_swap(
    user_id: UUID,
    from_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Будущие невыполненные дежурства коллеги — для выбора взаимного обмена датами."""
    if from_date is None:
        from_date = date.today()
    rows = (
        db.query(DutyAssignment)
        .filter(
            DutyAssignment.user_id == user_id,
            DutyAssignment.date >= from_date,
            DutyAssignment.is_completed.is_(False),
        )
        .order_by(DutyAssignment.date, DutyAssignment.duty_type)
        .all()
    )
    return rows


@router.get("/swaps/incoming", response_model=List[DutySwapResponse])
def get_incoming_swaps(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Входящие запросы на обмен дежурством."""
    swaps = (
        db.query(DutySwap)
        .filter(DutySwap.target_id == current_user.id, DutySwap.status == "pending")
        .all()
    )
    return [DutySwapResponse.from_orm_with_names(s) for s in swaps]


@router.get("/swaps/my", response_model=List[DutySwapResponse])
def get_my_swaps(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Мои исходящие запросы на обмен."""
    swaps = (
        db.query(DutySwap)
        .filter(DutySwap.requester_id == current_user.id)
        .order_by(DutySwap.created_at.desc())
        .all()
    )
    return [DutySwapResponse.from_orm_with_names(s) for s in swaps]


@router.post("/swap-request", response_model=DutySwapResponse, status_code=201)
def create_swap_request(
    data: DutySwapCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Запрос на обмен дежурством. Сотрудник A → Сотрудник B.
    Работает для обоих типов (LUNCH и CLEANING).
    """
    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == data.assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")
    if assignment.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Это не ваше дежурство")
    if assignment.is_completed:
        raise HTTPException(status_code=400, detail="Нельзя обменяться уже выполненным дежурством")

    target = db.query(User).filter(User.id == data.target_user_id, User.deleted_at.is_(None)).first()
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Check no pending swap already exists for this assignment
    existing = db.query(DutySwap).filter(
        DutySwap.assignment_id == data.assignment_id,
        DutySwap.status == "pending",
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Уже есть активный запрос на обмен этим дежурством")

    target_assignment_id = None
    if data.target_assignment_id:
        other = (
            db.query(DutyAssignment)
            .filter(DutyAssignment.id == data.target_assignment_id)
            .first()
        )
        if not other:
            raise HTTPException(status_code=404, detail="Назначение коллеги не найдено")
        if other.user_id != data.target_user_id:
            raise HTTPException(
                status_code=400,
                detail="Выбранное дежурство не принадлежит этому сотруднику",
            )
        if other.is_completed:
            raise HTTPException(status_code=400, detail="Нельзя обменяться с уже выполненным дежурством")
        if other.duty_type != assignment.duty_type:
            raise HTTPException(
                status_code=400,
                detail="Обмен только между дежурствами одного типа (обед или уборка)",
            )
        target_assignment_id = other.id

    swap = DutySwap(
        requester_id=current_user.id,
        target_id=data.target_user_id,
        assignment_id=data.assignment_id,
        target_assignment_id=target_assignment_id,
        status="pending",
    )
    db.add(swap)
    db.commit()
    db.refresh(swap)

    # Push notification → целевому сотруднику
    notify_user(
        target,
        title="Запрос на обмен дежурством",
        body=f"{current_user.full_name} хочет поменяться с вами дежурством",
        data={"type": "duty_swap_request", "swap_id": str(swap.id)},
    )

    return DutySwapResponse.from_orm_with_names(swap)


@router.patch("/swap/{swap_id}/accept")
def accept_swap(
    swap_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Принять обмен дежурством. Дежурство передаётся target-пользователю.
    Одобрение Admin не требуется — это автоматически.
    """
    swap = db.query(DutySwap).filter(DutySwap.id == swap_id).first()
    if not swap:
        raise HTTPException(status_code=404, detail="Запрос не найден")
    if current_user.id != swap.target_id:
        raise HTTPException(status_code=403, detail="Только адресат может принять обмен")
    if swap.status != "pending":
        raise HTTPException(status_code=400, detail="Запрос уже обработан")

    assignment = db.query(DutyAssignment).filter(DutyAssignment.id == swap.assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Назначение не найдено")

    if swap.target_assignment_id:
        other = (
            db.query(DutyAssignment)
            .filter(DutyAssignment.id == swap.target_assignment_id)
            .first()
        )
        if not other:
            raise HTTPException(status_code=404, detail="Назначение коллеги не найдено")
        uid_a = assignment.user_id
        uid_b = other.user_id
        assignment.user_id = uid_b
        other.user_id = uid_a
        msg = (
            f"Обмен принят: вы поменялись датами ({assignment.duty_type.value}). "
            f"Ваше дежурство теперь на {assignment.date}, коллеги — на {other.date}."
        )
        old_user_id = str(uid_a)
        new_user_id = str(uid_b)
    else:
        old_user_id = str(assignment.user_id)
        assignment.user_id = swap.target_id
        new_user_id = str(swap.target_id)
        msg = (
            f"Обмен принят. Дежурство {assignment.date} ({assignment.duty_type.value}) "
            f"передано вам; подтверждение админа после выполнения — как обычно."
        )

    swap.status = "accepted"
    swap.responded_by = current_user.id
    swap.responded_at = datetime.now(timezone.utc)

    db.commit()

    # Push notification → инициатору обмена
    requester = db.query(User).filter(User.id == swap.requester_id).first()
    notify_user(
        requester,
        title="Обмен дежурством принят",
        body=f"{current_user.full_name} принял(а) ваш запрос на обмен",
        data={"type": "duty_swap_accepted", "swap_id": str(swap.id)},
    )

    return {
        "message": msg,
        "new_user_id": new_user_id,
        "old_user_id": old_user_id,
        "mutual": bool(swap.target_assignment_id),
    }


@router.patch("/swap/{swap_id}/reject")
def reject_swap(
    swap_id: UUID,
    note: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    swap = db.query(DutySwap).filter(DutySwap.id == swap_id).first()
    if not swap:
        raise HTTPException(status_code=404, detail="Запрос не найден")
    if current_user.id != swap.target_id:
        raise HTTPException(status_code=403, detail="Только адресат может отклонить")
    if swap.status != "pending":
        raise HTTPException(status_code=400, detail="Запрос уже обработан")

    swap.status = "rejected"
    swap.response_note = note
    swap.responded_by = current_user.id
    swap.responded_at = datetime.now(timezone.utc)
    db.commit()

    # Push notification → инициатору обмена
    requester = db.query(User).filter(User.id == swap.requester_id).first()
    notify_user(
        requester,
        title="Обмен дежурством отклонён",
        body=f"{current_user.full_name} отклонил(а) ваш запрос на обмен",
        data={"type": "duty_swap_rejected", "swap_id": str(swap.id)},
    )

    return {"message": "Запрос отклонён"}

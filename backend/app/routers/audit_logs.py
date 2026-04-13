"""
Эндпоинты для просмотра аудит-лога действий администраторов.
Только ADMIN и SUPER_ADMIN.
"""
from datetime import date
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.audit_log import AuditLog
from app.models.user import User
from app.utils.dependencies import require_admin

router = APIRouter(prefix="/audit-logs", tags=["Аудит"])


@router.get("", response_model=List[dict])
def list_audit_logs(
    actor_id: Optional[UUID] = Query(default=None, description="Фильтр по автору действия"),
    action: Optional[str] = Query(default=None, description="Фильтр по типу действия"),
    entity: Optional[str] = Query(default=None, description="Фильтр по сущности (User, Attendance, ...)"),
    entity_id: Optional[UUID] = Query(default=None, description="Фильтр по ID записи"),
    date_from: Optional[date] = Query(default=None, description="Начало периода (включительно)"),
    date_to: Optional[date] = Query(default=None, description="Конец периода (включительно)"),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Список записей аудит-лога с фильтрами. Только для Admin / SuperAdmin."""
    q = db.query(AuditLog)

    if actor_id:
        q = q.filter(AuditLog.user_id == actor_id)
    if action:
        q = q.filter(AuditLog.action.ilike(f"%{action}%"))
    if entity:
        q = q.filter(AuditLog.entity == entity)
    if entity_id:
        q = q.filter(AuditLog.entity_id == entity_id)
    if date_from:
        q = q.filter(AuditLog.created_at >= date_from)
    if date_to:
        from datetime import datetime, time, timezone
        end_of_day = datetime.combine(date_to, time(23, 59, 59)).replace(tzinfo=timezone.utc)
        q = q.filter(AuditLog.created_at <= end_of_day)

    logs = q.order_by(AuditLog.created_at.desc()).offset(skip).limit(limit).all()

    result = []
    for log in logs:
        actor = db.query(User).filter(User.id == log.user_id).first()
        result.append({
            "id": str(log.id),
            "actor_id": str(log.user_id) if log.user_id else None,
            "actor_name": actor.full_name if actor else "Система",
            "action": log.action,
            "entity": log.entity,
            "entity_id": str(log.entity_id) if log.entity_id else None,
            "old_value": log.old_value,
            "new_value": log.new_value,
            "ip_address": log.ip_address,
            "created_at": log.created_at.isoformat() if log.created_at else None,
        })

    return result


@router.get("/{log_id}", response_model=dict)
def get_audit_log(
    log_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Детальный просмотр записи аудит-лога."""
    log = db.query(AuditLog).filter(AuditLog.id == log_id).first()
    if not log:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Запись аудита не найдена")

    actor = db.query(User).filter(User.id == log.user_id).first()
    return {
        "id": str(log.id),
        "actor_id": str(log.user_id) if log.user_id else None,
        "actor_name": actor.full_name if actor else "Система",
        "action": log.action,
        "entity": log.entity,
        "entity_id": str(log.entity_id) if log.entity_id else None,
        "old_value": log.old_value,
        "new_value": log.new_value,
        "ip_address": log.ip_address,
        "created_at": log.created_at.isoformat() if log.created_at else None,
    }

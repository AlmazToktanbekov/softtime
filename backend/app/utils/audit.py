"""
Utility for writing to audit_logs table.
Import and call write_audit() from any router that needs Admin action logging.
"""
from typing import Optional
from uuid import UUID

from fastapi import Request
from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog


def write_audit(
    db: Session,
    *,
    actor_id: UUID,
    action: str,
    entity: str,
    entity_id: Optional[UUID] = None,
    old_value: Optional[dict] = None,
    new_value: Optional[dict] = None,
    request: Optional[Request] = None,
) -> AuditLog:
    ip = None
    if request is not None:
        forwarded = request.headers.get("X-Forwarded-For")
        ip = forwarded.split(",")[0].strip() if forwarded else request.client.host if request.client else None

    log = AuditLog(
        user_id=actor_id,
        action=action,
        entity=entity,
        entity_id=entity_id,
        old_value=old_value,
        new_value=new_value,
        ip_address=ip,
    )
    db.add(log)
    # Caller is responsible for db.commit()
    return log

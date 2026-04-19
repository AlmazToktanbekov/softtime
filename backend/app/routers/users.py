import os
import shutil
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.audit_log import AuditLog
from app.models.user import User, UserRole, UserStatus
from app.schemas.user import (
    AvatarResponse,
    PaginatedUsers,
    UserCreate,
    UserApproveRequest,
    UserRejectRequest,
    UserDetail,
    UserListItem,
    UserStatusUpdateRequest,
    UserUpdateRequest,
)
from app.utils.security import get_password_hash
from app.utils.audit import write_audit
from app.utils.dependencies import get_current_user, require_admin, require_admin_or_teamlead
from app.utils.fcm import notify_user, notify_users

router = APIRouter(prefix="/users", tags=["Пользователи"])

_UPLOADS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads", "avatars")
_AVATAR_MAX_BYTES = 5 * 1024 * 1024  # 5 MB
_AVATAR_ALLOWED_TYPES = {"image/jpeg", "image/png"}
_AVATAR_EXT = {"image/jpeg": ".jpg", "image/png": ".png"}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _base_query(db: Session):
    """All non-deleted users."""
    return db.query(User).filter(User.deleted_at.is_(None))


def _apply_filters(q, *, status=None, role=None, team_name=None, search=None):
    if status:
        q = q.filter(User.status == status)
    if role:
        q = q.filter(User.role == role)
    if team_name:
        q = q.filter(User.team_name == team_name)
    if search:
        pattern = f"%{search}%"
        q = q.filter(
            or_(
                User.full_name.ilike(pattern),
                User.email.ilike(pattern),
                User.username.ilike(pattern),
            )
        )
    return q


def _get_user_or_404(db: Session, user_id: uuid.UUID) -> User:
    user = _base_query(db).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    return user


def _serialise(user: User) -> dict:
    """Snapshot a user's mutable fields for AuditLog old/new_value."""
    return {
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
        "role": user.role.value,
        "status": user.status.value,
        "team_name": user.team_name,
        "mentor_id": str(user.mentor_id) if user.mentor_id else None,
        "hired_at": user.hired_at.isoformat() if user.hired_at else None,
        "admin_comment": user.admin_comment,
    }


# ── GET /users ─────────────────────────────────────────────────────────────────

@router.get("", response_model=PaginatedUsers)
def list_users(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: Optional[UserStatus] = Query(None),
    role: Optional[UserRole] = Query(None),
    team_name: Optional[str] = Query(None),
    search: Optional[str] = Query(None, min_length=1),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    q = _base_query(db)

    # TEAM_LEAD sees only their mentees
    if current_user.role == UserRole.TEAM_LEAD:
        q = q.filter(User.mentor_id == current_user.id)

    q = _apply_filters(q, status=status, role=role, team_name=team_name, search=search)

    total = q.count()
    items = q.order_by(User.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return PaginatedUsers(
        items=[UserListItem.model_validate(u) for u in items],
        total=total,
        page=page,
        limit=limit,
    )


# ── GET /users/pending ─────────────────────────────────────────────────────────

@router.get("/pending", response_model=PaginatedUsers)
def list_pending(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    q = _base_query(db).filter(User.status == UserStatus.PENDING)
    total = q.count()
    items = q.order_by(User.created_at.asc()).offset((page - 1) * limit).limit(limit).all()

    return PaginatedUsers(
        items=[UserListItem.model_validate(u) for u in items],
        total=total,
        page=page,
        limit=limit,
    )


# ── GET /users/{user_id} ───────────────────────────────────────────────────────

@router.get("/{user_id}", response_model=UserDetail)
def get_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    target = _get_user_or_404(db, user_id)

    is_admin = current_user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN)
    is_teamlead_of = (
        current_user.role == UserRole.TEAM_LEAD
        and target.mentor_id == current_user.id
    )
    is_self = target.id == current_user.id

    if not (is_admin or is_teamlead_of or is_self):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Нет доступа к этому профилю")

    return UserDetail.model_validate(target)


# ── PUT /users/{user_id} ───────────────────────────────────────────────────────

@router.put("/{user_id}", response_model=UserDetail)
def update_user(
    user_id: uuid.UUID,
    data: UserUpdateRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    target = _get_user_or_404(db, user_id)

    # Uniqueness checks for changed fields
    if data.email and data.email != target.email:
        if db.query(User).filter(User.email == data.email, User.id != user_id).first():
            raise HTTPException(status.HTTP_409_CONFLICT, detail="Email уже используется")

    if data.phone and data.phone != target.phone:
        if db.query(User).filter(User.phone == data.phone, User.id != user_id).first():
            raise HTTPException(status.HTTP_409_CONFLICT, detail="Телефон уже используется")

    # Validate mentor_id if provided
    if data.mentor_id is not None:
        if data.mentor_id == user_id:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Нельзя назначить пользователя своим ментором")
        mentor = _base_query(db).filter(User.id == data.mentor_id).first()
        if not mentor:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Ментор не найден")

    old_snapshot = _serialise(target)

    patch = data.model_dump(exclude_unset=True)
    for field, value in patch.items():
        setattr(target, field, value)

    write_audit(
        db,
        actor_id=current_user.id,
        action="UPDATE_USER",
        entity="User",
        entity_id=target.id,
        old_value=old_snapshot,
        new_value=_serialise(target),
        request=request,
    )
    db.commit()
    db.refresh(target)
    return UserDetail.model_validate(target)


# ── PATCH /users/{user_id}/status ─────────────────────────────────────────────

@router.patch("/{user_id}/status", response_model=UserDetail)
def change_status(
    user_id: uuid.UUID,
    data: UserStatusUpdateRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    target = _get_user_or_404(db, user_id)

    # Guard: cannot change SUPER_ADMIN status
    if target.role == UserRole.SUPER_ADMIN and current_user.role != UserRole.SUPER_ADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Нельзя изменить статус Super Admin")

    # Guard: cannot block/delete yourself
    if target.id == current_user.id and data.status in (UserStatus.BLOCKED, UserStatus.DELETED):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Нельзя заблокировать или удалить себя")

    old_status = target.status
    target.status = data.status

    if data.comment:
        target.admin_comment = data.comment

    write_audit(
        db,
        actor_id=current_user.id,
        action="UPDATE_STATUS",
        entity="User",
        entity_id=target.id,
        old_value={"status": old_status.value},
        new_value={"status": data.status.value, "comment": data.comment},
        request=request,
    )
    db.commit()
    db.refresh(target)

    if old_status == UserStatus.PENDING and data.status == UserStatus.ACTIVE:
        notify_user(
            target,
            title="Аккаунт активирован",
            body="Ваш аккаунт активирован администратором",
            data={"type": "account_activated"},
        )
    elif data.status == UserStatus.BLOCKED:
        notify_user(
            target,
            title="Аккаунт заблокирован",
            body="Ваш аккаунт заблокирован. Обратитесь к администратору",
            data={"type": "account_blocked"},
        )

    return UserDetail.model_validate(target)


def _archive_value(value: str, suffix: str) -> str:
    """Уникализировать email/username при мягком удалении."""
    if not value:
        return value
    return f"{value}__archived__{suffix}"


def _can_manage(current_user: User, target: User) -> bool:
    """Проверить, может ли current_user управлять target."""
    if current_user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        return True
    if current_user.role != UserRole.TEAM_LEAD:
        return False
    if target.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        return False
    return target.mentor_id == current_user.id or (
        current_user.team_id is not None and target.team_id == current_user.team_id
    )


# ── POST /users (Admin создаёт сотрудника напрямую) ───────────────────────────

@router.post("", response_model=UserDetail, status_code=status.HTTP_201_CREATED)
def create_user(
    data: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Email уже используется")
    if db.query(User).filter(User.username == data.username).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Логин уже занят")

    phone = data.phone or "+996000000000"
    if data.phone and db.query(User).filter(User.phone == phone).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Телефон уже зарегистрирован")

    user = User(
        full_name=data.full_name,
        email=data.email,
        phone=phone,
        username=data.username,
        password_hash=get_password_hash(data.password),
        role=data.role,
        status=UserStatus.ACTIVE,
        team_name=data.team_name,
        hired_at=data.hired_at,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    write_audit(
        db,
        actor_id=current_user.id,
        action="CREATE_USER",
        entity="User",
        entity_id=user.id,
        new_value={"full_name": user.full_name, "email": user.email},
    )
    db.commit()
    return UserDetail.model_validate(user)


# ── PATCH /users/{user_id}/approve ────────────────────────────────────────────

@router.patch("/{user_id}/approve")
def approve_user(
    user_id: uuid.UUID,
    data: UserApproveRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    if target.status != UserStatus.PENDING:
        return {"message": "Уже обработано или не в статусе ожидания"}

    target.status = UserStatus.ACTIVE
    target.role = data.role
    if data.mentor_id is not None:
        target.mentor_id = data.mentor_id
    if data.comment:
        target.admin_comment = (target.admin_comment or "") + f"\n[approve] {data.comment}"

    write_audit(
        db,
        actor_id=current_user.id,
        action="APPROVE_USER",
        entity="User",
        entity_id=user_id,
        old_value={"status": "PENDING"},
        new_value={"status": "ACTIVE", "role": data.role},
    )
    db.commit()

    # Push notification → сотруднику
    notify_user(
        target,
        title="Аккаунт подтверждён",
        body="Ваша заявка одобрена. Добро пожаловать!",
        data={"type": "account_approved"},
    )

    return {"message": "Сотрудник подтверждён и активирован"}


# ── PATCH /users/{user_id}/reject ─────────────────────────────────────────────

@router.patch("/{user_id}/reject")
def reject_user(
    user_id: uuid.UUID,
    data: UserRejectRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    target.status = UserStatus.DELETED
    target.deleted_at = datetime.now(timezone.utc)
    if data.reason:
        target.admin_comment = (target.admin_comment or "") + f"\n[reject] {data.reason}"

    write_audit(
        db,
        actor_id=current_user.id,
        action="REJECT_USER",
        entity="User",
        entity_id=user_id,
        new_value={"status": "DELETED", "reason": data.reason},
    )
    db.commit()

    # Push notification → сотруднику
    notify_user(
        target,
        title="Заявка отклонена",
        body=data.reason or "Ваша заявка на доступ отклонена администратором",
        data={"type": "account_rejected"},
    )

    return {"message": "Заявка отклонена", "reason": data.reason}


# ── PATCH /users/{user_id}/activate ───────────────────────────────────────────

@router.patch("/{user_id}/activate")
def activate_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    if not _can_manage(current_user, target):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Нет доступа к этому сотруднику")

    old_status = target.status.value
    target.status = UserStatus.ACTIVE
    target.deleted_at = None

    write_audit(
        db,
        actor_id=current_user.id,
        action="ACTIVATE_USER",
        entity="User",
        entity_id=user_id,
        old_value={"status": old_status},
        new_value={"status": "ACTIVE"},
    )
    db.commit()
    return {"message": "Сотрудник активирован"}


# ── PATCH /users/{user_id}/deactivate ─────────────────────────────────────────

@router.patch("/{user_id}/deactivate")
def deactivate_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    if not _can_manage(current_user, target):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Нет доступа к этому сотруднику")

    old_status = target.status.value
    suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    target.status = UserStatus.DELETED
    target.deleted_at = datetime.now(timezone.utc)
    target.username = _archive_value(target.username, suffix)
    target.email = _archive_value(target.email, suffix)

    write_audit(
        db,
        actor_id=current_user.id,
        action="DEACTIVATE_USER",
        entity="User",
        entity_id=user_id,
        old_value={"status": old_status},
        new_value={"status": "DELETED"},
    )
    db.commit()
    return {"message": "Сотрудник деактивирован"}




# ── DELETE /users/{user_id} ────────────────────────────────────────────────────

@router.delete("/{user_id}", status_code=status.HTTP_200_OK)
def delete_user(
    user_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    target = _get_user_or_404(db, user_id)

    if target.id == current_user.id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Нельзя удалить себя")

    if target.role == UserRole.SUPER_ADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Нельзя удалить Super Admin")

    old_snapshot = _serialise(target)

    target.status = UserStatus.DELETED
    target.deleted_at = datetime.now(timezone.utc)

    write_audit(
        db,
        actor_id=current_user.id,
        action="DELETE_USER",
        entity="User",
        entity_id=target.id,
        old_value=old_snapshot,
        new_value={"status": UserStatus.DELETED.value, "deleted_at": target.deleted_at.isoformat()},
        request=request,
    )
    db.commit()
    return {"message": f"Пользователь {target.username} помечен как удалённый"}


# ── PATCH /users/{user_id}/reset-password ────────────────────────────────────

class ResetPasswordRequest(BaseModel):
    new_password: str

@router.patch("/{user_id}/reset-password")
def reset_user_password(
    user_id: uuid.UUID,
    data: ResetPasswordRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Админ сбрасывает пароль сотруднику."""
    if len(data.new_password) < 6:
        raise HTTPException(status_code=400, detail="Пароль должен быть минимум 6 символов")

    target = _get_user_or_404(db, user_id)

    if target.role == UserRole.SUPER_ADMIN and current_user.role != UserRole.SUPER_ADMIN:
        raise HTTPException(status_code=403, detail="Нельзя сбросить пароль Super Admin")

    target.password_hash = get_password_hash(data.new_password)

    write_audit(
        db,
        actor_id=current_user.id,
        action="RESET_PASSWORD",
        entity="User",
        entity_id=target.id,
        new_value={"reset_by": str(current_user.id)},
        request=request,
    )
    db.commit()
    return {"message": f"Пароль пользователя {target.full_name} успешно сброшен"}


# ── PATCH /users/me/avatar ────────────────────────────────────────────────────

@router.patch("/me/avatar", response_model=AvatarResponse)
def upload_my_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload avatar for the currently authenticated user."""
    if file.content_type not in _AVATAR_ALLOWED_TYPES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Допустимые форматы: JPEG, PNG",
        )
    contents = file.file.read()
    if len(contents) > _AVATAR_MAX_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Максимальный размер файла: 5 MB",
        )
    ext = _AVATAR_EXT[file.content_type]
    filename = f"{current_user.id}{ext}"
    os.makedirs(_UPLOADS_DIR, exist_ok=True)
    dest_path = os.path.join(_UPLOADS_DIR, filename)
    with open(dest_path, "wb") as f:
        f.write(contents)
    avatar_url = f"/uploads/avatars/{filename}"
    current_user.avatar_url = avatar_url
    db.commit()
    return AvatarResponse(avatar_url=avatar_url)


# ── PATCH /users/{user_id}/avatar ─────────────────────────────────────────────

@router.patch("/{user_id}/avatar", response_model=AvatarResponse)
def upload_avatar(
    user_id: uuid.UUID,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Permission: admin can set anyone's avatar; user can only set own
    is_admin = current_user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN)
    if not is_admin and current_user.id != user_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Можно загружать только свой аватар")

    target = _get_user_or_404(db, user_id)

    # Validate content type
    if file.content_type not in _AVATAR_ALLOWED_TYPES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Допустимые форматы: JPEG, PNG",
        )

    # Read and validate size
    contents = file.file.read()
    if len(contents) > _AVATAR_MAX_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Максимальный размер файла: 5 MB",
        )

    # Save file
    ext = _AVATAR_EXT[file.content_type]
    filename = f"{user_id}{ext}"
    os.makedirs(_UPLOADS_DIR, exist_ok=True)
    dest_path = os.path.join(_UPLOADS_DIR, filename)

    with open(dest_path, "wb") as f:
        f.write(contents)

    avatar_url = f"/uploads/avatars/{filename}"
    target.avatar_url = avatar_url
    db.commit()

    return AvatarResponse(avatar_url=avatar_url)

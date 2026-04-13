from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.utils.security import decode_token
from app.utils.redis_client import is_token_blacklisted

_bearer = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    payload = decode_token(token)

    if not payload or payload.get("type") != "access":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Недействительный токен")

    jti = payload.get("jti")
    if jti and is_token_blacklisted(jti):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Токен отозван")

    user_id = payload.get("sub")
    user: Optional[User] = db.query(User).filter(User.id == user_id).first()

    if not user or user.deleted_at is not None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Пользователь не найден")

    if user.status != UserStatus.ACTIVE:
        _status_message = {
            UserStatus.PENDING: "Аккаунт ожидает подтверждения",
            UserStatus.BLOCKED: "Аккаунт заблокирован",
            UserStatus.DELETED: "Аккаунт удалён",
            UserStatus.LEAVE: "Аккаунт на паузе",
            UserStatus.WARNING: "Аккаунт активен (предупреждение)",
        }
        detail = _status_message.get(user.status, "Аккаунт неактивен")
        # WARNING status still allows access
        if user.status != UserStatus.WARNING:
            raise HTTPException(status.HTTP_403_FORBIDDEN, detail=detail)

    return user


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Требуется роль Admin")
    return current_user


def require_admin_or_teamlead(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN, UserRole.TEAM_LEAD):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Требуется роль Admin или Team Lead")
    return current_user


def require_super_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != UserRole.SUPER_ADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Требуется роль Super Admin")
    return current_user

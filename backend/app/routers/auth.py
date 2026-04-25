from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.schemas.auth import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserMeResponse,
)
from app.utils.dependencies import get_current_user
from app.utils.fcm import notify_users
from app.utils.redis_client import (
    blacklist_token,
    clear_failed_attempts,
    is_ip_blocked,
    is_login_blocked,
    is_token_blacklisted,
    record_failed_attempt,
)
from app.utils.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_password_hash,
    token_ttl_seconds,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["Аутентификация"])

_MENTOR_ROLES = (UserRole.TEAM_LEAD, UserRole.ADMIN, UserRole.SUPER_ADMIN)


@router.get("/register/mentors")
def list_register_mentors(
    db: Session = Depends(get_db),
):
    """Список менторов для регистрации стажёра. Публичный доступ."""
    users = (
        db.query(User)
        .filter(
            User.deleted_at.is_(None),
            User.status == UserStatus.ACTIVE,
            User.role.in_(_MENTOR_ROLES),
        )
        .order_by(User.full_name)
        .all()
    )
    return [{"id": str(u.id), "full_name": u.full_name, "role": u.role.value} for u in users]


# ── POST /register ─────────────────────────────────────────────────────────────

@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    """
    Self-registration. Account is created with status PENDING.
    Admin must approve before the user can log in.
    """
    # Uniqueness checks — 409 Conflict (exclude soft-deleted users)
    if db.query(User).filter(User.email == data.email, User.deleted_at.is_(None)).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Email уже зарегистрирован")
    if db.query(User).filter(User.username == data.username, User.deleted_at.is_(None)).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Логин уже занят")
    if db.query(User).filter(User.phone == data.phone, User.deleted_at.is_(None)).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Телефон уже зарегистрирован")

    mentor_id = None
    if data.role == UserRole.INTERN and data.mentor_id:
        mentor = (
            db.query(User)
            .filter(
                User.id == data.mentor_id,
                User.deleted_at.is_(None),
                User.status == UserStatus.ACTIVE,
                User.role.in_(_MENTOR_ROLES),
            )
            .first()
        )
        if not mentor:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Выберите ментора из списка (активный сотрудник с ролью ментора или администратор)",
            )
        mentor_id = data.mentor_id

    user = User(
        full_name=data.full_name,
        email=data.email,
        phone=data.phone,
        username=data.username,
        password_hash=get_password_hash(data.password),
        role=data.role,
        status=UserStatus.PENDING,
        hired_at=date.today(),
        mentor_id=mentor_id,
    )
    db.add(user)
    db.commit()

    # Push notification → все Admin и Super Admin
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
        title="Новый сотрудник ожидает подтверждения",
        body=f"{data.full_name} ждёт одобрения",
        data={"type": "new_pending_user"},
    )

    # Возвращаем временный токен, чтобы Flutter мог сразу загрузить аватар
    access_token, _ = create_access_token(str(user.id), user.role.value)
    return {
        "message": "Заявка отправлена. Ожидайте подтверждения администратором.",
        "upload_token": access_token,
        "user_id": str(user.id),
    }


# ── POST /login ────────────────────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """
    Login with username (or email) + password.
    Brute-force protection: 5 failed attempts → 15-minute block.
    """
    client_ip = request.headers.get("X-Real-IP") or request.headers.get("X-Forwarded-For", "").split(",")[0].strip() or (request.client.host if request.client else "unknown")
    username_key = data.username.lower()

    if is_ip_blocked(client_ip):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Слишком много неудачных попыток. Попробуйте через 1 час.",
        )

    if is_login_blocked(username_key):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Слишком много неудачных попыток. Попробуйте через 15 минут.",
        )

    user: Optional[User] = db.query(User).filter(
        (User.username == data.username) | (User.email == data.username)
    ).first()

    if not user or not verify_password(data.password, user.password_hash):
        count = record_failed_attempt(username_key, ip=client_ip)
        remaining = max(0, 5 - count)
        detail = "Неверный логин или пароль."
        if remaining > 0:
            detail += f" Осталось попыток: {remaining}."
        else:
            detail = "Слишком много неудачных попыток. Попробуйте через 15 минут."
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=detail)

    # Status checks
    _blocked_statuses = {
        UserStatus.PENDING: "Аккаунт ожидает подтверждения администратором",
        UserStatus.BLOCKED: "Аккаунт заблокирован. Обратитесь к администратору",
        UserStatus.DELETED: "Аккаунт удалён",
    }
    if user.status in _blocked_statuses:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=_blocked_statuses[user.status])

    # Success — clear brute-force counter
    clear_failed_attempts(username_key)

    user_id = str(user.id)
    role = user.role.value

    access_token, _ = create_access_token(user_id, role)
    refresh_token, _ = create_refresh_token(user_id, role)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserMeResponse.model_validate(user),
    )


# ── POST /refresh ──────────────────────────────────────────────────────────────

@router.post("/refresh", response_model=TokenResponse)
def refresh(data: RefreshRequest, db: Session = Depends(get_db)):
    """
    Exchange a refresh token for a new access + refresh token pair.
    Old refresh token is blacklisted (rotation).
    """
    payload = decode_token(data.refresh_token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Недействительный refresh token")

    jti = payload.get("jti", "")
    if is_token_blacklisted(jti):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Refresh token отозван")

    user_id = payload.get("sub")
    user: Optional[User] = db.query(User).filter(User.id == user_id).first()
    if not user or user.status in (UserStatus.BLOCKED, UserStatus.DELETED, UserStatus.PENDING):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Пользователь не найден или неактивен")

    # Rotate: blacklist old refresh token
    blacklist_token(jti, token_ttl_seconds(payload))

    role = user.role.value
    uid = str(user.id)
    new_access, _ = create_access_token(uid, role)
    new_refresh, _ = create_refresh_token(uid, role)

    return TokenResponse(
        access_token=new_access,
        refresh_token=new_refresh,
        user=UserMeResponse.model_validate(user),
    )


# ── POST /logout ───────────────────────────────────────────────────────────────

@router.post("/logout", status_code=status.HTTP_200_OK)
def logout(
    data: LogoutRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Invalidate the refresh token. The access token expires naturally (15 min).
    """
    payload = decode_token(data.refresh_token)
    if payload and payload.get("sub") == str(current_user.id):
        jti = payload.get("jti", "")
        blacklist_token(jti, token_ttl_seconds(payload))

    return {"message": "Выход выполнен успешно"}


# ── GET /me ────────────────────────────────────────────────────────────────────

@router.get("/me", response_model=UserMeResponse)
def me(current_user: User = Depends(get_current_user)):
    return current_user


# ── POST /fcm-token ────────────────────────────────────────────────────────────

@router.post("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
def update_fcm_token(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Сохранить FCM токен устройства для push-уведомлений.
    Тело: {"fcm_token": "..."}
    """
    token = (data.get("fcm_token") or "").strip()
    if not token:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="fcm_token обязателен")
    current_user.fcm_token = token
    db.commit()

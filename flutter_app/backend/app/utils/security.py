import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import settings

# bcrypt cost factor 12 as per CLAUDE.md requirements
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)

PASSWORD_RE = re.compile(r"^(?=.*[A-Z])(?=.*\d).{8,}$")

_BRUTE_FORCE_MAX = 5
_BRUTE_FORCE_WINDOW = 15 * 60  # 15 minutes in seconds


# ── Passwords ─────────────────────────────────────────────────────────────────

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def validate_password_strength(password: str) -> None:
    """Raise ValueError if password doesn't meet requirements."""
    if not PASSWORD_RE.match(password):
        raise ValueError(
            "Пароль должен содержать минимум 8 символов, "
            "одну заглавную букву и одну цифру."
        )


# ── JWT ───────────────────────────────────────────────────────────────────────

def _build_token(data: dict, token_type: str, expires_delta: timedelta) -> tuple[str, str]:
    """Return (encoded_token, jti). jti is used for blacklisting."""
    jti = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    payload = {
        **data,
        "jti": jti,
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
    }
    token = jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return token, jti


def create_access_token(user_id: str, role: str) -> tuple[str, str]:
    """Return (access_token, jti)."""
    return _build_token(
        {"sub": user_id, "role": role},
        "access",
        timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    )


def create_refresh_token(user_id: str, role: str) -> tuple[str, str]:
    """Return (refresh_token, jti)."""
    return _build_token(
        {"sub": user_id, "role": role},
        "refresh",
        timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )


def decode_token(token: str) -> Optional[dict]:
    """Return decoded payload or None on any error."""
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return None


def token_ttl_seconds(payload: dict) -> int:
    """Seconds remaining until token expires (0 if already expired)."""
    exp = payload.get("exp", 0)
    remaining = int(exp - datetime.now(timezone.utc).timestamp())
    return max(remaining, 0)

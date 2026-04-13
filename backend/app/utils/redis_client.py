"""
Redis helper for:
  - JWT blacklist (logout / token rotation)
  - Brute-force login protection
"""
from typing import Optional

import redis

from app.config import settings

_pool: Optional[redis.ConnectionPool] = None


def _get_pool() -> redis.ConnectionPool:
    global _pool
    if _pool is None:
        _pool = redis.ConnectionPool.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            max_connections=20,
        )
    return _pool


def get_redis() -> redis.Redis:
    return redis.Redis(connection_pool=_get_pool())


# ── Token blacklist ────────────────────────────────────────────────────────────

def blacklist_token(jti: str, ttl_seconds: int) -> None:
    """Mark a token as invalid for the remainder of its lifetime."""
    if ttl_seconds > 0:
        get_redis().setex(f"bl:{jti}", ttl_seconds, "1")


def is_token_blacklisted(jti: str) -> bool:
    return bool(get_redis().exists(f"bl:{jti}"))


# ── Brute-force protection ─────────────────────────────────────────────────────

_MAX_ATTEMPTS = 5
_BLOCK_SECONDS = 15 * 60  # 15 minutes


def _bf_key(username: str) -> str:
    return f"bf:{username.lower()}"


def is_login_blocked(username: str) -> bool:
    val = get_redis().get(_bf_key(username))
    return bool(val and int(val) >= _MAX_ATTEMPTS)


def record_failed_attempt(username: str) -> int:
    """Increment counter. Returns new count. Sets expiry on first hit."""
    key = _bf_key(username)
    r = get_redis()
    count = r.incr(key)
    if count == 1:
        r.expire(key, _BLOCK_SECONDS)
    return count


def clear_failed_attempts(username: str) -> None:
    get_redis().delete(_bf_key(username))

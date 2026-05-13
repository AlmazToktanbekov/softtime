"""
Redis helper for:
  - JWT blacklist (logout / token rotation)
  - Brute-force login protection

Redis is optional: if unavailable, all checks degrade gracefully
(tokens are not blacklisted, brute-force protection is disabled).
"""
import logging
from typing import Optional

import redis

from app.config import settings

logger = logging.getLogger(__name__)

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


def get_redis() -> Optional[redis.Redis]:
    try:
        r = redis.Redis(connection_pool=_get_pool())
        r.ping()
        return r
    except Exception:
        return None


# ── Token blacklist ────────────────────────────────────────────────────────────

def blacklist_token(jti: str, ttl_seconds: int) -> None:
    r = get_redis()
    if r and ttl_seconds > 0:
        try:
            r.setex(f"bl:{jti}", ttl_seconds, "1")
        except Exception:
            logger.warning("Redis unavailable: token blacklist skipped")


def is_token_blacklisted(jti: str) -> bool:
    r = get_redis()
    if not r:
        return False
    try:
        return bool(r.exists(f"bl:{jti}"))
    except Exception:
        return False


# ── Brute-force protection ─────────────────────────────────────────────────────

_MAX_ATTEMPTS = 5
_BLOCK_SECONDS = 15 * 60  # 15 minutes
_IP_MAX_ATTEMPTS = 20     # block IP after 20 failed attempts
_IP_BLOCK_SECONDS = 60 * 60  # 1 hour


def _bf_key(username: str) -> str:
    return f"bf:{username.lower()}"


def _ip_key(ip: str) -> str:
    return f"bf_ip:{ip}"


def is_login_blocked(username: str) -> bool:
    r = get_redis()
    if not r:
        return False
    try:
        val = r.get(_bf_key(username))
        return bool(val and int(val) >= _MAX_ATTEMPTS)
    except Exception:
        return False


def is_ip_blocked(ip: str) -> bool:
    r = get_redis()
    if not r:
        return False
    try:
        val = r.get(_ip_key(ip))
        return bool(val and int(val) >= _IP_MAX_ATTEMPTS)
    except Exception:
        return False


def record_failed_attempt(username: str, ip: Optional[str] = None) -> int:
    r = get_redis()
    if not r:
        return 0
    try:
        key = _bf_key(username)
        count = r.incr(key)
        if count == 1:
            r.expire(key, _BLOCK_SECONDS)
        if ip:
            ip_key = _ip_key(ip)
            r.incr(ip_key)
            r.expire(ip_key, _IP_BLOCK_SECONDS)
        return count
    except Exception:
        return 0


def clear_failed_attempts(username: str) -> None:
    r = get_redis()
    if not r:
        return
    try:
        r.delete(_bf_key(username))
    except Exception:
        pass


# ── Public redis_client reference ─────────────────────────────────────────────

redis_client = get_redis()

"""
Unit tests for auth logic.

Mocks:
  - Redis → no real Redis needed
  - SQLAlchemy Session → no real DB needed
  - Password hashing → uses real bcrypt (fast rounds in tests)

Run:  pytest backend/tests/test_auth.py -v
"""
import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch, call

import pytest

# ── Security helpers ──────────────────────────────────────────────────────────

class TestPasswordHashing:
    def test_hash_is_not_plain(self):
        from app.utils.security import get_password_hash
        h = get_password_hash("Secret1!")
        assert h != "Secret1!"
        assert len(h) > 20

    def test_verify_correct(self):
        from app.utils.security import get_password_hash, verify_password
        h = get_password_hash("Secret1!")
        assert verify_password("Secret1!", h) is True

    def test_verify_wrong(self):
        from app.utils.security import get_password_hash, verify_password
        h = get_password_hash("Secret1!")
        assert verify_password("WrongPass1!", h) is False


class TestPasswordValidation:
    def test_valid_password(self):
        from app.utils.security import validate_password_strength
        validate_password_strength("Secure123")  # should not raise

    def test_too_short(self):
        from app.utils.security import validate_password_strength
        with pytest.raises(ValueError, match="8 символов"):
            validate_password_strength("Ab1")

    def test_no_uppercase(self):
        from app.utils.security import validate_password_strength
        with pytest.raises(ValueError):
            validate_password_strength("password1")

    def test_no_digit(self):
        from app.utils.security import validate_password_strength
        with pytest.raises(ValueError):
            validate_password_strength("PasswordOnly")

    def test_exactly_8_chars(self):
        from app.utils.security import validate_password_strength
        validate_password_strength("Secure12")  # should not raise


class TestJWT:
    def test_access_token_roundtrip(self):
        from app.utils.security import create_access_token, decode_token
        uid = str(uuid.uuid4())
        token, jti = create_access_token(uid, "EMPLOYEE")
        payload = decode_token(token)
        assert payload is not None
        assert payload["sub"] == uid
        assert payload["type"] == "access"
        assert payload["role"] == "EMPLOYEE"
        assert payload["jti"] == jti

    def test_refresh_token_roundtrip(self):
        from app.utils.security import create_refresh_token, decode_token
        uid = str(uuid.uuid4())
        token, jti = create_refresh_token(uid, "ADMIN")
        payload = decode_token(token)
        assert payload is not None
        assert payload["type"] == "refresh"
        assert payload["jti"] == jti

    def test_decode_invalid_token(self):
        from app.utils.security import decode_token
        assert decode_token("not.a.token") is None

    def test_decode_tampered_token(self):
        from app.utils.security import create_access_token, decode_token
        token, _ = create_access_token(str(uuid.uuid4()), "EMPLOYEE")
        tampered = token[:-5] + "XXXXX"
        assert decode_token(tampered) is None

    def test_jti_is_unique(self):
        from app.utils.security import create_access_token
        uid = str(uuid.uuid4())
        _, jti1 = create_access_token(uid, "EMPLOYEE")
        _, jti2 = create_access_token(uid, "EMPLOYEE")
        assert jti1 != jti2

    def test_token_ttl_positive(self):
        from app.config import settings
        from app.utils.security import create_access_token, decode_token, token_ttl_seconds
        token, _ = create_access_token(str(uuid.uuid4()), "EMPLOYEE")
        payload = decode_token(token)
        ttl = token_ttl_seconds(payload)
        expected = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        assert ttl > 0
        assert ttl <= expected + 5  # allow 5s clock skew


# ── Redis helpers ─────────────────────────────────────────────────────────────

class TestRedisHelpers:
    @patch("app.utils.redis_client.get_redis")
    def test_blacklist_token(self, mock_get_redis):
        r = MagicMock()
        mock_get_redis.return_value = r
        from app.utils.redis_client import blacklist_token
        blacklist_token("some-jti", 900)
        r.setex.assert_called_once_with("bl:some-jti", 900, "1")

    @patch("app.utils.redis_client.get_redis")
    def test_blacklist_token_zero_ttl_skipped(self, mock_get_redis):
        r = MagicMock()
        mock_get_redis.return_value = r
        from app.utils.redis_client import blacklist_token
        blacklist_token("jti", 0)
        r.setex.assert_not_called()

    @patch("app.utils.redis_client.get_redis")
    def test_is_blacklisted_true(self, mock_get_redis):
        r = MagicMock()
        r.exists.return_value = 1
        mock_get_redis.return_value = r
        from app.utils.redis_client import is_token_blacklisted
        assert is_token_blacklisted("jti") is True

    @patch("app.utils.redis_client.get_redis")
    def test_is_blacklisted_false(self, mock_get_redis):
        r = MagicMock()
        r.exists.return_value = 0
        mock_get_redis.return_value = r
        from app.utils.redis_client import is_token_blacklisted
        assert is_token_blacklisted("jti") is False

    @patch("app.utils.redis_client.get_redis")
    def test_login_blocked_when_count_gte_5(self, mock_get_redis):
        r = MagicMock()
        r.get.return_value = "5"
        mock_get_redis.return_value = r
        from app.utils.redis_client import is_login_blocked
        assert is_login_blocked("alice") is True

    @patch("app.utils.redis_client.get_redis")
    def test_login_not_blocked_when_count_lt_5(self, mock_get_redis):
        r = MagicMock()
        r.get.return_value = "3"
        mock_get_redis.return_value = r
        from app.utils.redis_client import is_login_blocked
        assert is_login_blocked("alice") is False

    @patch("app.utils.redis_client.get_redis")
    def test_record_first_attempt_sets_expiry(self, mock_get_redis):
        r = MagicMock()
        r.incr.return_value = 1
        mock_get_redis.return_value = r
        from app.utils.redis_client import record_failed_attempt
        count = record_failed_attempt("alice")
        assert count == 1
        r.expire.assert_called_once_with("bf:alice", 900)

    @patch("app.utils.redis_client.get_redis")
    def test_record_subsequent_attempt_no_expiry_reset(self, mock_get_redis):
        r = MagicMock()
        r.incr.return_value = 3
        mock_get_redis.return_value = r
        from app.utils.redis_client import record_failed_attempt
        record_failed_attempt("alice")
        r.expire.assert_not_called()

    @patch("app.utils.redis_client.get_redis")
    def test_clear_attempts(self, mock_get_redis):
        r = MagicMock()
        mock_get_redis.return_value = r
        from app.utils.redis_client import clear_failed_attempts
        clear_failed_attempts("alice")
        r.delete.assert_called_once_with("bf:alice")


# ── Register endpoint ─────────────────────────────────────────────────────────

def _make_user(**kwargs) -> MagicMock:
    """Helper: create a mock User with sensible defaults."""
    u = MagicMock()
    u.id = uuid.uuid4()
    u.full_name = kwargs.get("full_name", "Test User")
    u.email = kwargs.get("email", "test@example.com")
    u.phone = kwargs.get("phone", "+99612345678")
    u.username = kwargs.get("username", "testuser")
    u.password_hash = kwargs.get("password_hash", "hash")
    u.role = kwargs.get("role", MagicMock(value="EMPLOYEE"))
    u.status = kwargs.get("status", MagicMock())
    u.team_name = None
    u.team_id = kwargs.get("team_id", None)
    u.mentor_id = kwargs.get("mentor_id", None)
    u.mentor_full_name = kwargs.get("mentor_full_name", None)
    u.avatar_url = None
    u.hired_at = None
    u.created_at = datetime.now(timezone.utc)
    u.deleted_at = None
    return u


class TestRegisterEndpoint:
    def _call(self, db, payload):
        from app.routers.auth import register
        from app.schemas.auth import RegisterRequest
        req = RegisterRequest(**payload)
        return register(req, db)

    def _valid_payload(self):
        return {
            "full_name": "Ivan Petrov",
            "email": "ivan@example.com",
            "phone": "+99612345678",
            "username": "ivanp",
            "password": "Secret123",
        }

    def test_success(self):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None
        result = self._call(db, self._valid_payload())
        assert "Заявка отправлена" in result["message"]
        db.add.assert_called_once()
        db.commit.assert_called_once()

    def test_duplicate_email_raises_409(self):
        from fastapi import HTTPException
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = _make_user()
        with pytest.raises(HTTPException) as exc:
            self._call(db, self._valid_payload())
        assert exc.value.status_code == 409

    def test_weak_password_raises_422(self):
        from pydantic import ValidationError
        payload = self._valid_payload()
        payload["password"] = "weakpass"
        from app.schemas.auth import RegisterRequest
        with pytest.raises(ValidationError):
            RegisterRequest(**payload)

    def test_invalid_phone_raises_422(self):
        from pydantic import ValidationError
        payload = self._valid_payload()
        payload["phone"] = "12345"
        from app.schemas.auth import RegisterRequest
        with pytest.raises(ValidationError):
            RegisterRequest(**payload)

    def test_short_username_raises_422(self):
        from pydantic import ValidationError
        payload = self._valid_payload()
        payload["username"] = "ab"
        from app.schemas.auth import RegisterRequest
        with pytest.raises(ValidationError):
            RegisterRequest(**payload)


# ── Login endpoint ────────────────────────────────────────────────────────────

class TestLoginEndpoint:
    def _call(self, db, username, password, request=None):
        from app.routers.auth import login
        from app.schemas.auth import LoginRequest
        req = LoginRequest(username=username, password=password)
        return login(req, request or MagicMock(), db)

    @patch("app.routers.auth.is_login_blocked", return_value=False)
    @patch("app.routers.auth.clear_failed_attempts")
    @patch("app.routers.auth.verify_password", return_value=True)
    def test_success(self, mock_verify, mock_clear, mock_blocked):
        from app.models.user import UserStatus, UserRole
        db = MagicMock()
        user = _make_user()
        user.status = UserStatus.ACTIVE
        user.role = UserRole.EMPLOYEE
        db.query.return_value.filter.return_value.first.return_value = user

        result = self._call(db, "testuser", "Secret123")

        assert result.access_token
        assert result.refresh_token
        assert result.token_type == "bearer"
        mock_clear.assert_called_once_with("testuser")

    @patch("app.routers.auth.is_login_blocked", return_value=True)
    def test_blocked_raises_429(self, _):
        from fastapi import HTTPException
        db = MagicMock()
        with pytest.raises(HTTPException) as exc:
            self._call(db, "testuser", "Secret123")
        assert exc.value.status_code == 429

    @patch("app.routers.auth.is_login_blocked", return_value=False)
    @patch("app.routers.auth.record_failed_attempt", return_value=1)
    def test_wrong_password_raises_401(self, mock_record, mock_blocked):
        from fastapi import HTTPException
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None
        with pytest.raises(HTTPException) as exc:
            self._call(db, "testuser", "WrongPass1!")
        assert exc.value.status_code == 401
        mock_record.assert_called_once()
        assert mock_record.call_args[0][0] == "testuser"

    @patch("app.routers.auth.is_login_blocked", return_value=False)
    @patch("app.routers.auth.verify_password", return_value=True)
    def test_pending_user_raises_403(self, mock_verify, mock_blocked):
        from fastapi import HTTPException
        from app.models.user import UserStatus
        db = MagicMock()
        user = _make_user()
        user.status = UserStatus.PENDING
        db.query.return_value.filter.return_value.first.return_value = user
        with pytest.raises(HTTPException) as exc:
            self._call(db, "testuser", "Secret123")
        assert exc.value.status_code == 403
        assert "подтверждения" in exc.value.detail

    @patch("app.routers.auth.is_login_blocked", return_value=False)
    @patch("app.routers.auth.verify_password", return_value=True)
    def test_blocked_user_raises_403(self, mock_verify, mock_blocked):
        from fastapi import HTTPException
        from app.models.user import UserStatus
        db = MagicMock()
        user = _make_user()
        user.status = UserStatus.BLOCKED
        db.query.return_value.filter.return_value.first.return_value = user
        with pytest.raises(HTTPException) as exc:
            self._call(db, "testuser", "Secret123")
        assert exc.value.status_code == 403


# ── Refresh endpoint ──────────────────────────────────────────────────────────

class TestRefreshEndpoint:
    @patch("app.routers.auth.is_token_blacklisted", return_value=False)
    @patch("app.routers.auth.blacklist_token")
    def test_success_rotates_token(self, mock_blacklist, mock_blacklisted):
        from app.models.user import UserStatus, UserRole
        from app.routers.auth import refresh
        from app.schemas.auth import RefreshRequest
        from app.utils.security import create_refresh_token

        uid = str(uuid.uuid4())
        refresh_token, old_jti = create_refresh_token(uid, "EMPLOYEE")

        db = MagicMock()
        user = _make_user()
        user.id = uuid.UUID(uid)
        user.status = UserStatus.ACTIVE
        user.role = UserRole.EMPLOYEE
        db.query.return_value.filter.return_value.first.return_value = user

        result = refresh(RefreshRequest(refresh_token=refresh_token), db)

        assert result.access_token
        assert result.refresh_token != refresh_token
        mock_blacklist.assert_called_once()
        assert mock_blacklist.call_args[0][0] == old_jti

    @patch("app.routers.auth.is_token_blacklisted", return_value=True)
    def test_blacklisted_token_raises_401(self, _):
        from fastapi import HTTPException
        from app.routers.auth import refresh
        from app.schemas.auth import RefreshRequest
        from app.utils.security import create_refresh_token
        token, _ = create_refresh_token(str(uuid.uuid4()), "EMPLOYEE")
        db = MagicMock()
        with pytest.raises(HTTPException) as exc:
            refresh(RefreshRequest(refresh_token=token), db)
        assert exc.value.status_code == 401

    def test_invalid_token_raises_401(self):
        from fastapi import HTTPException
        from app.routers.auth import refresh
        from app.schemas.auth import RefreshRequest
        db = MagicMock()
        with pytest.raises(HTTPException) as exc:
            refresh(RefreshRequest(refresh_token="garbage"), db)
        assert exc.value.status_code == 401

    def test_access_token_not_accepted(self):
        from fastapi import HTTPException
        from app.routers.auth import refresh
        from app.schemas.auth import RefreshRequest
        from app.utils.security import create_access_token
        token, _ = create_access_token(str(uuid.uuid4()), "EMPLOYEE")
        db = MagicMock()
        with pytest.raises(HTTPException) as exc:
            refresh(RefreshRequest(refresh_token=token), db)
        assert exc.value.status_code == 401


# ── Logout endpoint ───────────────────────────────────────────────────────────

class TestLogoutEndpoint:
    @patch("app.routers.auth.blacklist_token")
    def test_success_blacklists_refresh(self, mock_blacklist):
        from app.routers.auth import logout
        from app.schemas.auth import LogoutRequest
        from app.utils.security import create_refresh_token

        uid = str(uuid.uuid4())
        token, jti = create_refresh_token(uid, "EMPLOYEE")

        current_user = MagicMock()
        current_user.id = uuid.UUID(uid)

        result = logout(LogoutRequest(refresh_token=token), current_user)
        assert "Выход" in result["message"]
        mock_blacklist.assert_called_once()
        assert mock_blacklist.call_args[0][0] == jti

    @patch("app.routers.auth.blacklist_token")
    def test_foreign_token_not_blacklisted(self, mock_blacklist):
        """Cannot blacklist another user's refresh token."""
        from app.routers.auth import logout
        from app.schemas.auth import LogoutRequest
        from app.utils.security import create_refresh_token

        other_uid = str(uuid.uuid4())
        token, _ = create_refresh_token(other_uid, "EMPLOYEE")

        current_user = MagicMock()
        current_user.id = uuid.uuid4()  # different user

        logout(LogoutRequest(refresh_token=token), current_user)
        mock_blacklist.assert_not_called()

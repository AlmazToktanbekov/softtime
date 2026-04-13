import os
import secrets

from sqlalchemy.orm import Session

from app.models.user import User, UserRole, UserStatus
from app.models.office_network import OfficeNetwork, QRToken
from app.utils.security import get_password_hash

# Credentials читаются из .env — никогда не хардкодятся в коде
_ADMIN_USERNAME = os.getenv("DEFAULT_ADMIN_USERNAME", "admin")
_ADMIN_EMAIL = os.getenv("DEFAULT_ADMIN_EMAIL", "admin@softjol.com")
_ADMIN_PASSWORD = os.getenv("DEFAULT_ADMIN_PASSWORD", "changeme_in_production")
_ADMIN_PHONE = os.getenv("DEFAULT_ADMIN_PHONE", "+99600000000")


def ensure_default_data(db: Session) -> None:
    changed = False

    # Default SUPER_ADMIN account
    admin = db.query(User).filter(
        (User.username == _ADMIN_USERNAME) | (User.email == _ADMIN_EMAIL)
    ).first()

    if not admin:
        admin = User(
            full_name="Super Admin",
            email=_ADMIN_EMAIL,
            phone=_ADMIN_PHONE,
            username=_ADMIN_USERNAME,
            password_hash=get_password_hash(_ADMIN_PASSWORD),
            role=UserRole.SUPER_ADMIN,
            status=UserStatus.ACTIVE,
        )
        db.add(admin)
        changed = True
    else:
        # Ensure admin stays active and has correct role
        if admin.role not in (UserRole.SUPER_ADMIN, UserRole.ADMIN):
            admin.role = UserRole.SUPER_ADMIN
            changed = True
        if admin.status != UserStatus.ACTIVE:
            admin.status = UserStatus.ACTIVE
            changed = True

    # Default office network
    if not db.query(OfficeNetwork).first():
        db.add(
            OfficeNetwork(
                name="Softjol Office",
                public_ip="127.0.0.1",
                ip_range="192.168.0.0/16",
                description="Default development network",
                is_active=True,
            )
        )
        changed = True

    # Default QR tokens
    if not db.query(QRToken).filter(QRToken.type == "attendance", QRToken.is_active.is_(True)).first():
        db.add(QRToken(token=secrets.token_urlsafe(32), type="attendance", is_active=True))
        changed = True

    if not db.query(QRToken).filter(QRToken.type == "duty", QRToken.is_active.is_(True)).first():
        db.add(QRToken(token=secrets.token_urlsafe(32), type="duty", is_active=True))
        changed = True

    if changed:
        db.commit()

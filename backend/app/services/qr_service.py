import qrcode
import io
import base64
import secrets
from datetime import datetime
from typing import Optional, Tuple
from sqlalchemy.orm import Session
from app.models.office_network import QRToken


def validate_qr_token(token: str, db: Session) -> Tuple[bool, str]:
    """Validate QR token. Returns (is_valid, message)."""
    qr = db.query(QRToken).filter(
        QRToken.token == token,
        QRToken.is_active == True
    ).first()

    if not qr:
        return False, "QR-код недействителен"

    if qr.expires_at and qr.expires_at < datetime.utcnow():
        return False, "QR-код просрочен"

    return True, "OK"


def generate_qr_token(db: Session, token_type: str = "static") -> QRToken:
    """Generate a new QR token."""
    token = secrets.token_urlsafe(32)
    qr_token = QRToken(token=token, type=token_type, is_active=True)
    db.add(qr_token)
    db.commit()
    db.refresh(qr_token)
    return qr_token


def generate_qr_image_base64(token: str) -> str:
    """Generate QR code image as base64 string."""
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(token)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    buffer.seek(0)
    return base64.b64encode(buffer.read()).decode("utf-8")


def get_active_qr_token(db: Session) -> Optional[QRToken]:
    """Get currently active QR token."""
    return db.query(QRToken).filter(QRToken.is_active == True).order_by(QRToken.created_at.desc()).first()

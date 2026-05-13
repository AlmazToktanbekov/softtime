from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum as SQLEnum
from sqlalchemy.sql import func
import enum
from app.database import Base


class OfficeNetwork(Base):
    __tablename__ = "office_networks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    public_ip = Column(String(45), nullable=True)
    ip_range = Column(String(50), nullable=True)
    description = Column(String(255), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class QRToken(Base):
    __tablename__ = "qr_tokens"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String(255), unique=True, nullable=False, index=True)
    type = Column(String(50), default="static")   # static, dynamic
    is_active = Column(Boolean, default=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

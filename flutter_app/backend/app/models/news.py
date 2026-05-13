import uuid
import enum

from sqlalchemy import Column, String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class NewsType(str, enum.Enum):
    announcement = "announcement"
    system_update = "system_update"
    urgent = "urgent"
    general = "general"


class News(Base):
    __tablename__ = "news"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    title = Column(String(255), nullable=False)
    content = Column(Text, nullable=False)
    type = Column(String(50), default=NewsType.general, nullable=False)
    image_url = Column(String(500), nullable=True)
    target_audience = Column(String(100), default="all")
    pinned = Column(Boolean, default=False, nullable=False)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    author = relationship("User", foreign_keys=[created_by])
    reads = relationship("NewsRead", back_populates="news", cascade="all, delete-orphan")


class NewsRead(Base):
    __tablename__ = "news_reads"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    news_id = Column(UUID(as_uuid=True), ForeignKey("news.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    read_at = Column(DateTime(timezone=True), server_default=func.now())

    news = relationship("News", back_populates="reads")
    user = relationship("User", foreign_keys=[user_id])

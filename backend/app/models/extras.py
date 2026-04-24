"""
Модели для новых фич: дневник стажера, оценки, бронирование переговорки, кудосы, очки.
"""
import uuid
import enum

from sqlalchemy import (
    Column, String, Text, DateTime, Date, Integer, Float,
    ForeignKey, Boolean, Enum as SQLEnum
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


# ──────────────────────────────────────────────────────────────────────────────
# Дневник стажера
# ──────────────────────────────────────────────────────────────────────────────

class InternDiary(Base):
    """Ежедневный мини-отчет стажера."""
    __tablename__ = "intern_diaries"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    intern_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    diary_date = Column(Date, nullable=False)
    learned_today = Column(Text, nullable=False)  # Что нового узнал
    difficulties = Column(Text, nullable=True)    # Трудности
    plans_tomorrow = Column(Text, nullable=True)  # Планы на завтра
    mood = Column(Integer, nullable=True)         # Настроение 1-5
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    intern = relationship("User", foreign_keys=[intern_id])


# ──────────────────────────────────────────────────────────────────────────────
# Оценка стажера ментором
# ──────────────────────────────────────────────────────────────────────────────

class InternEvaluation(Base):
    """Периодическая оценка стажера ментором."""
    __tablename__ = "intern_evaluations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    intern_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    mentor_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    eval_period = Column(String(20), nullable=False)  # e.g. "2025-W01"
    motivation_score = Column(Integer, nullable=False)   # 1-5
    knowledge_score = Column(Integer, nullable=False)    # 1-5
    communication_score = Column(Integer, nullable=False) # 1-5
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    intern = relationship("User", foreign_keys=[intern_id])
    mentor = relationship("User", foreign_keys=[mentor_id])


# ──────────────────────────────────────────────────────────────────────────────
# Бронирование переговорки
# ──────────────────────────────────────────────────────────────────────────────

class Room(Base):
    """Переговорная комната."""
    __tablename__ = "rooms"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(100), nullable=False)
    capacity = Column(Integer, default=10)
    description = Column(Text, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    bookings = relationship("RoomBooking", back_populates="room")


class RoomBooking(Base):
    """Бронирование переговорки."""
    __tablename__ = "room_bookings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id = Column(UUID(as_uuid=True), ForeignKey("rooms.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(200), nullable=False)
    booking_date = Column(Date, nullable=False)
    start_time = Column(String(5), nullable=False)  # "09:00"
    end_time = Column(String(5), nullable=False)    # "10:30"
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    room = relationship("Room", back_populates="bookings")
    user = relationship("User", foreign_keys=[user_id])


# ──────────────────────────────────────────────────────────────────────────────
# Кудосы (доска благодарностей)
# ──────────────────────────────────────────────────────────────────────────────

class Kudos(Base):
    """Публичная благодарность коллеге."""
    __tablename__ = "kudos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    from_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    to_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    message = Column(Text, nullable=False)
    emoji = Column(String(10), default="🙌")  # Эмодзи-реакция
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    from_user = relationship("User", foreign_keys=[from_user_id])
    to_user = relationship("User", foreign_keys=[to_user_id])


# ──────────────────────────────────────────────────────────────────────────────
# Геймификация: очки и призы
# ──────────────────────────────────────────────────────────────────────────────

class UserPoints(Base):
    """Баланс очков пользователя."""
    __tablename__ = "user_points"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, unique=True, index=True)
    total_points = Column(Integer, default=0)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", foreign_keys=[user_id])
    transactions = relationship("PointTransaction", back_populates="user_points")


class PointTransaction(Base):
    """История начисления/списания очков."""
    __tablename__ = "point_transactions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_points_id = Column(UUID(as_uuid=True), ForeignKey("user_points.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    amount = Column(Integer, nullable=False)   # >0 начисление, <0 списание
    reason = Column(String(200), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user_points = relationship("UserPoints", back_populates="transactions")
    user = relationship("User", foreign_keys=[user_id])


class Reward(Base):
    """Приз в магазине очков."""
    __tablename__ = "rewards"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    cost_points = Column(Integer, nullable=False)
    emoji = Column(String(10), default="🎁")
    is_active = Column(Boolean, default=True)
    stock = Column(Integer, default=-1)  # -1 = безлимитно
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class RewardClaim(Base):
    """Покупка приза."""
    __tablename__ = "reward_claims"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    reward_id = Column(UUID(as_uuid=True), ForeignKey("rewards.id"), nullable=False)
    status = Column(String(20), default="pending")  # pending / approved / rejected
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", foreign_keys=[user_id])
    reward = relationship("Reward", foreign_keys=[reward_id])

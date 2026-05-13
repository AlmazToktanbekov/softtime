"""
Роутеры для новых фич:
- Дневник стажера
- Оценки стажера ментором
- Бронирование переговорки
- Кудосы (доска благодарностей)
- Геймификация (очки и призы)
- Ментор-дашборд (список подопечных)
"""
import uuid
from datetime import date, datetime, timezone
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.models.task import Task, TaskStatus
from app.models.attendance import Attendance
from app.models.extras import (
    InternDiary, InternEvaluation,
    Room, RoomBooking,
    Kudos,
    UserPoints, PointTransaction, Reward, RewardClaim,
)
from app.utils.dependencies import get_current_user, require_admin, require_admin_or_teamlead
from app.utils.fcm import notify_user

router = APIRouter(tags=["Новые фичи"])


# ══════════════════════════════════════════════════════════════════════════════
# SCHEMAS
# ══════════════════════════════════════════════════════════════════════════════

class DiaryCreate(BaseModel):
    diary_date: date
    learned_today: str
    difficulties: Optional[str] = None
    plans_tomorrow: Optional[str] = None
    mood: Optional[int] = None  # 1-5

class DiaryResponse(DiaryCreate):
    id: UUID
    intern_id: UUID
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class EvaluationCreate(BaseModel):
    intern_id: UUID
    eval_period: str  # "2025-W01"
    motivation_score: int
    knowledge_score: int
    communication_score: int
    comment: Optional[str] = None

class EvaluationResponse(EvaluationCreate):
    id: UUID
    mentor_id: UUID
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class RoomCreate(BaseModel):
    name: str
    capacity: int = 10
    description: Optional[str] = None

class RoomResponse(RoomCreate):
    id: UUID
    is_active: bool
    model_config = ConfigDict(from_attributes=True)


class BookingCreate(BaseModel):
    room_id: UUID
    title: str
    booking_date: date
    start_time: str
    end_time: str

class BookingResponse(BookingCreate):
    id: UUID
    user_id: UUID
    user_name: Optional[str] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class KudosCreate(BaseModel):
    to_user_id: UUID
    message: str
    emoji: str = "🙌"

class KudosResponse(BaseModel):
    id: UUID
    from_user_id: UUID
    from_user_name: Optional[str] = None
    to_user_id: UUID
    to_user_name: Optional[str] = None
    message: str
    emoji: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class PointsResponse(BaseModel):
    user_id: UUID
    total_points: int
    model_config = ConfigDict(from_attributes=True)


class RewardCreate(BaseModel):
    title: str
    description: Optional[str] = None
    cost_points: int
    emoji: str = "🎁"
    stock: int = -1

class RewardResponse(RewardCreate):
    id: UUID
    is_active: bool
    model_config = ConfigDict(from_attributes=True)


class MenteeProgress(BaseModel):
    id: UUID
    full_name: str
    avatar_url: Optional[str]
    hired_at: Optional[date]
    tasks_total: int
    tasks_done: int
    checked_in_today: bool
    days_worked: int
    latest_evaluation: Optional[EvaluationResponse]


# ══════════════════════════════════════════════════════════════════════════════
# DIARY — Дневник стажера
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/intern/diary", response_model=DiaryResponse, status_code=201, summary="Создать запись в дневнике")
def create_diary(
    data: DiaryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.INTERN, UserRole.EMPLOYEE, UserRole.TEAM_LEAD):
        if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
            raise HTTPException(status_code=403, detail="Только стажеры могут вести дневник")

    # Обновить если запись на эту дату уже есть
    existing = db.query(InternDiary).filter(
        InternDiary.intern_id == current_user.id,
        InternDiary.diary_date == data.diary_date
    ).first()

    if existing:
        for k, v in data.model_dump().items():
            setattr(existing, k, v)
        db.commit()
        db.refresh(existing)
        return existing

    diary = InternDiary(intern_id=current_user.id, **data.model_dump())
    db.add(diary)
    db.commit()
    db.refresh(diary)
    return diary


@router.get("/intern/diary", response_model=List[DiaryResponse], summary="Мои записи в дневнике")
def list_my_diary(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(InternDiary).filter(
        InternDiary.intern_id == current_user.id
    ).order_by(InternDiary.diary_date.desc()).limit(30).all()


@router.get("/intern/{intern_id}/diary", response_model=List[DiaryResponse], summary="Дневник стажера (для ментора)")
def list_intern_diary(
    intern_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    intern = db.query(User).filter(User.id == intern_id).first()
    if not intern:
        raise HTTPException(status_code=404, detail="Стажер не найден")
    if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN, UserRole.TEAM_LEAD):
        if intern.mentor_id != current_user.id:
            raise HTTPException(status_code=403, detail="Нет доступа")
    return db.query(InternDiary).filter(
        InternDiary.intern_id == intern_id
    ).order_by(InternDiary.diary_date.desc()).limit(30).all()


# ══════════════════════════════════════════════════════════════════════════════
# EVALUATIONS — Оценки стажера
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/intern/evaluations", response_model=EvaluationResponse, status_code=201)
def create_evaluation(
    data: EvaluationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.TEAM_LEAD, UserRole.ADMIN, UserRole.SUPER_ADMIN):
        raise HTTPException(status_code=403, detail="Только ментор может ставить оценки")

    intern = db.query(User).filter(User.id == data.intern_id).first()
    if not intern:
        raise HTTPException(status_code=404, detail="Стажер не найден")

    # Проверить, не ставили ли уже оценку за этот период
    existing = db.query(InternEvaluation).filter(
        InternEvaluation.intern_id == data.intern_id,
        InternEvaluation.mentor_id == current_user.id,
        InternEvaluation.eval_period == data.eval_period,
    ).first()
    if existing:
        for k, v in data.model_dump().items():
            setattr(existing, k, v)
        db.commit()
        db.refresh(existing)
        return existing

    evaluation = InternEvaluation(mentor_id=current_user.id, **data.model_dump())
    db.add(evaluation)
    db.commit()
    db.refresh(evaluation)

    # Уведомить стажера
    avg = (data.motivation_score + data.knowledge_score + data.communication_score) / 3
    notify_user(intern, title="📊 Новая оценка", body=f"Ваш ментор поставил оценку: {avg:.1f}/5.0")
    return evaluation


@router.get("/intern/{intern_id}/evaluations", response_model=List[EvaluationResponse])
def list_intern_evaluations(
    intern_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    intern = db.query(User).filter(User.id == intern_id).first()
    if not intern:
        raise HTTPException(status_code=404, detail="Стажер не найден")
    if current_user.id != intern_id:
        if current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN, UserRole.TEAM_LEAD):
            raise HTTPException(status_code=403, detail="Нет доступа")
    return db.query(InternEvaluation).filter(
        InternEvaluation.intern_id == intern_id
    ).order_by(InternEvaluation.created_at.desc()).all()


# ══════════════════════════════════════════════════════════════════════════════
# MENTOR DASHBOARD — Панель ментора
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/mentor/mentees", response_model=List[MenteeProgress], summary="Мои подопечные")
def get_my_mentees(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in (UserRole.TEAM_LEAD, UserRole.ADMIN, UserRole.SUPER_ADMIN):
        raise HTTPException(status_code=403, detail="Только ментор")

    mentees = db.query(User).filter(
        User.mentor_id == current_user.id,
        User.deleted_at.is_(None),
        User.status == UserStatus.ACTIVE,
    ).all()

    today = date.today()
    result = []

    for m in mentees:
        tasks_total = db.query(Task).filter(Task.assignee_id == m.id).count()
        tasks_done = db.query(Task).filter(
            Task.assignee_id == m.id,
            Task.status == TaskStatus.done
        ).count()

        checked_in = db.query(Attendance).filter(
            Attendance.user_id == m.id,
            func.date(Attendance.date) == today,
        ).first()

        days_worked = db.query(Attendance).filter(
            Attendance.user_id == m.id,
        ).count()

        latest_eval = db.query(InternEvaluation).filter(
            InternEvaluation.intern_id == m.id
        ).order_by(InternEvaluation.created_at.desc()).first()

        result.append(MenteeProgress(
            id=m.id,
            full_name=m.full_name,
            avatar_url=m.avatar_url,
            hired_at=m.hired_at,
            tasks_total=tasks_total,
            tasks_done=tasks_done,
            checked_in_today=checked_in is not None,
            days_worked=days_worked,
            latest_evaluation=EvaluationResponse.model_validate(latest_eval) if latest_eval else None,
        ))

    return result


# ══════════════════════════════════════════════════════════════════════════════
# ROOMS — Бронирование переговорки
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/rooms", response_model=List[RoomResponse])
def list_rooms(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Room).filter(Room.is_active.is_(True)).all()


@router.post("/rooms", response_model=RoomResponse, status_code=201)
def create_room(
    data: RoomCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    room = Room(**data.model_dump())
    db.add(room)
    db.commit()
    db.refresh(room)
    return room


@router.get("/rooms/bookings", response_model=List[BookingResponse])
def list_bookings(
    booking_date: Optional[date] = Query(None),
    room_id: Optional[UUID] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(RoomBooking)
    if booking_date:
        q = q.filter(RoomBooking.booking_date == booking_date)
    if room_id:
        q = q.filter(RoomBooking.room_id == room_id)
    bookings = q.order_by(RoomBooking.booking_date, RoomBooking.start_time).all()
    result = []
    for b in bookings:
        d = BookingResponse(
            id=b.id,
            room_id=b.room_id,
            user_id=b.user_id,
            user_name=b.user.full_name if b.user else None,
            title=b.title,
            booking_date=b.booking_date,
            start_time=b.start_time,
            end_time=b.end_time,
            created_at=b.created_at,
        )
        result.append(d)
    return result


@router.post("/rooms/bookings", response_model=BookingResponse, status_code=201)
def create_booking(
    data: BookingCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    room = db.query(Room).filter(Room.id == data.room_id, Room.is_active.is_(True)).first()
    if not room:
        raise HTTPException(status_code=404, detail="Комната не найдена")

    # Проверить конфликт
    conflict = db.query(RoomBooking).filter(
        RoomBooking.room_id == data.room_id,
        RoomBooking.booking_date == data.booking_date,
        RoomBooking.start_time < data.end_time,
        RoomBooking.end_time > data.start_time,
    ).first()
    if conflict:
        raise HTTPException(status_code=409, detail="Это время уже забронировано")

    booking = RoomBooking(user_id=current_user.id, **data.model_dump())
    db.add(booking)
    db.commit()
    db.refresh(booking)
    return BookingResponse(
        id=booking.id,
        room_id=booking.room_id,
        user_id=booking.user_id,
        user_name=current_user.full_name,
        title=booking.title,
        booking_date=booking.booking_date,
        start_time=booking.start_time,
        end_time=booking.end_time,
        created_at=booking.created_at,
    )


@router.delete("/rooms/bookings/{booking_id}")
def delete_booking(
    booking_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    b = db.query(RoomBooking).filter(RoomBooking.id == booking_id).first()
    if not b:
        raise HTTPException(status_code=404)
    if b.user_id != current_user.id and current_user.role not in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        raise HTTPException(status_code=403)
    db.delete(b)
    db.commit()
    return {"message": "Бронь удалена"}


# ══════════════════════════════════════════════════════════════════════════════
# KUDOS — Доска благодарностей
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/kudos", response_model=List[KudosResponse])
def list_kudos(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = db.query(Kudos).order_by(Kudos.created_at.desc()).offset(skip).limit(limit).all()
    result = []
    for k in items:
        result.append(KudosResponse(
            id=k.id,
            from_user_id=k.from_user_id,
            from_user_name=k.from_user.full_name if k.from_user else None,
            to_user_id=k.to_user_id,
            to_user_name=k.to_user.full_name if k.to_user else None,
            message=k.message,
            emoji=k.emoji,
            created_at=k.created_at,
        ))
    return result


@router.post("/kudos", response_model=KudosResponse, status_code=201)
def send_kudos(
    data: KudosCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if data.to_user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Нельзя отправить кудос себе")

    to_user = db.query(User).filter(User.id == data.to_user_id, User.deleted_at.is_(None)).first()
    if not to_user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    kudos = Kudos(from_user_id=current_user.id, **data.model_dump())
    db.add(kudos)

    # +5 очков получателю
    _add_points(db, to_user.id, 5, f"Кудос от {current_user.full_name}")
    db.commit()
    db.refresh(kudos)

    notify_user(to_user, title=f"{data.emoji} Кудос от {current_user.full_name}!", body=data.message)

    return KudosResponse(
        id=kudos.id,
        from_user_id=current_user.id,
        from_user_name=current_user.full_name,
        to_user_id=to_user.id,
        to_user_name=to_user.full_name,
        message=kudos.message,
        emoji=kudos.emoji,
        created_at=kudos.created_at,
    )


# ══════════════════════════════════════════════════════════════════════════════
# POINTS / REWARDS — Геймификация
# ══════════════════════════════════════════════════════════════════════════════

def _add_points(db: Session, user_id: UUID, amount: int, reason: str):
    """Внутренняя функция начисления очков."""
    up = db.query(UserPoints).filter(UserPoints.user_id == user_id).first()
    if not up:
        up = UserPoints(user_id=user_id, total_points=0)
        db.add(up)
        db.flush()
    up.total_points += amount
    txn = PointTransaction(user_points_id=up.id, user_id=user_id, amount=amount, reason=reason)
    db.add(txn)


@router.get("/points/me", response_model=PointsResponse, summary="Мои очки")
def my_points(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    up = db.query(UserPoints).filter(UserPoints.user_id == current_user.id).first()
    if not up:
        return PointsResponse(user_id=current_user.id, total_points=0)
    return PointsResponse(user_id=current_user.id, total_points=up.total_points)


@router.get("/points/leaderboard")
def leaderboard(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    rows = db.query(UserPoints, User).join(
        User, User.id == UserPoints.user_id
    ).order_by(UserPoints.total_points.desc()).limit(10).all()
    return [
        {"user_id": str(u.id), "full_name": u.full_name, "avatar_url": u.avatar_url, "points": up.total_points}
        for up, u in rows
    ]


@router.get("/rewards", response_model=List[RewardResponse])
def list_rewards(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Reward).filter(Reward.is_active.is_(True)).all()


@router.post("/rewards", response_model=RewardResponse, status_code=201)
def create_reward(
    data: RewardCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    reward = Reward(**data.model_dump())
    db.add(reward)
    db.commit()
    db.refresh(reward)
    return reward


@router.post("/rewards/{reward_id}/claim")
def claim_reward(
    reward_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    reward = db.query(Reward).filter(Reward.id == reward_id, Reward.is_active.is_(True)).first()
    if not reward:
        raise HTTPException(status_code=404, detail="Приз не найден")

    up = db.query(UserPoints).filter(UserPoints.user_id == current_user.id).first()
    if not up or up.total_points < reward.cost_points:
        raise HTTPException(status_code=400, detail="Недостаточно очков")

    _add_points(db, current_user.id, -reward.cost_points, f"Покупка: {reward.title}")
    claim = RewardClaim(user_id=current_user.id, reward_id=reward_id)
    db.add(claim)
    db.commit()
    return {"message": f"Запрос на '{reward.title}' отправлен администратору!"}

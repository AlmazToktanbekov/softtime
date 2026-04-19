import os
import uuid as uuid_lib
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.models.news import News, NewsRead
from app.schemas.news import (
    NewsCreate,
    NewsUpdate,
    NewsResponse,
    NewsReadStats,
)
from app.utils.dependencies import get_current_user, require_admin
from app.utils.audit import write_audit
from app.utils.fcm import notify_users

router = APIRouter(prefix="/news", tags=["Новости"])

_ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
_MAX_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB


@router.post("/upload-image")
async def upload_news_image(
    file: UploadFile = File(...),
    current_user: User = Depends(require_admin),
):
    """Загрузка изображения для новости. Возвращает URL."""
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in _ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Поддерживаются: jpg, jpeg, png, gif, webp")

    content = await file.read()
    if len(content) > _MAX_SIZE_BYTES:
        raise HTTPException(status_code=400, detail="Файл не должен превышать 5 МБ")

    upload_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        "uploads", "news"
    )
    os.makedirs(upload_dir, exist_ok=True)

    filename = f"{uuid_lib.uuid4()}{ext}"
    filepath = os.path.join(upload_dir, filename)
    with open(filepath, "wb") as f:
        f.write(content)

    return {"image_url": f"/uploads/news/{filename}"}


def _can_access_news(user: User, news: News) -> bool:
    if news.target_audience == "all":
        return True
    if news.target_audience == "teamlead" and user.role in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    ):
        return True
    return False


@router.get("", response_model=List[NewsResponse])
def list_news(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(News).order_by(News.pinned.desc(), News.created_at.desc())
    filtered = [n for n in query.all() if _can_access_news(current_user, n)]
    return filtered[skip : skip + limit]


@router.post("", response_model=NewsResponse, status_code=201)
def create_news(
    data: NewsCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Публикация новостей — только ADMIN (ТЗ §5.2)."""
    news = News(
        title=data.title,
        content=data.content,
        type=data.type.value,
        image_url=data.image_url,
        target_audience=data.target_audience,
        pinned=data.pinned,
        created_by=current_user.id,
    )
    db.add(news)
    db.commit()
    db.refresh(news)
    write_audit(db, actor_id=current_user.id, action="CREATE_NEWS",
                entity="News", entity_id=news.id,
                new_value={"title": news.title, "pinned": news.pinned})

    # Push notification → все активные сотрудники
    active_users = (
        db.query(User)
        .filter(
            User.deleted_at.is_(None),
            User.status == UserStatus.ACTIVE,
            User.fcm_token.isnot(None),
        )
        .all()
    )
    notify_users(
        active_users,
        title="Новая новость",
        body=news.title,
        data={"type": "new_news", "news_id": str(news.id)},
    )

    return news


# Статичные под-пути до /{news_id}, иначе UUID перехватит «stats»


@router.get("/unread", response_model=List[NewsResponse])
def list_unread_news(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Непрочитанные новости для текущего пользователя."""
    read_ids = {
        r[0]
        for r in db.query(NewsRead.news_id).filter(NewsRead.user_id == current_user.id).all()
    }
    all_news = db.query(News).order_by(News.pinned.desc(), News.created_at.desc()).all()
    return [n for n in all_news if _can_access_news(current_user, n) and n.id not in read_ids]


@router.get("/{news_id}/readers")
def get_news_readers(
    news_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Список сотрудников, прочитавших новость. Только для Admin."""
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")

    reads = db.query(NewsRead).filter(NewsRead.news_id == news_id).all()
    reader_ids = {r.user_id for r in reads}
    read_at_map = {r.user_id: r.read_at for r in reads}

    active_users = (
        db.query(User)
        .filter(
            User.deleted_at.is_(None),
            User.status == UserStatus.ACTIVE,
            User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        )
        .all()
    )

    result = []
    for user in active_users:
        result.append({
            "user_id": str(user.id),
            "full_name": user.full_name,
            "team_name": user.team_name,
            "has_read": user.id in reader_ids,
            "read_at": read_at_map[user.id].isoformat() if user.id in read_at_map else None,
        })

    result.sort(key=lambda x: (not x["has_read"], x["full_name"]))
    return result


@router.get("/{news_id}/stats", response_model=NewsReadStats)
def get_news_stats(
    news_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")

    total = (
        db.query(User)
        .filter(
            User.deleted_at.is_(None),
            User.status == UserStatus.ACTIVE,
            User.role.notin_([UserRole.ADMIN, UserRole.SUPER_ADMIN]),
        )
        .count()
    )
    read_count = db.query(NewsRead).filter(NewsRead.news_id == news_id).count()
    unread_count = max(total - read_count, 0)

    return NewsReadStats(
        total_employees=total,
        read_count=read_count,
        unread_count=unread_count,
    )


@router.patch("/{news_id}/pin")
def toggle_pin(
    news_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    news.pinned = not news.pinned
    db.commit()
    return {"message": "Закрепление изменено", "pinned": news.pinned}


@router.post("/{news_id}/read")
def mark_news_read(
    news_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")

    existing = (
        db.query(NewsRead)
        .filter(NewsRead.news_id == news_id, NewsRead.user_id == current_user.id)
        .first()
    )
    if existing:
        return {"message": "Уже прочитано"}

    read = NewsRead(news_id=news_id, user_id=current_user.id)
    db.add(read)
    db.commit()
    return {"message": "Отмечено как прочитанное"}


@router.get("/{news_id}", response_model=NewsResponse)
def get_news(
    news_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    if not _can_access_news(current_user, news):
        raise HTTPException(status_code=403, detail="Доступ запрещён")
    return news


@router.put("/{news_id}", response_model=NewsResponse)
def update_news(
    news_id: UUID,
    data: NewsUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    payload = data.model_dump(exclude_none=True)
    for key, value in payload.items():
        if key == "type" and value is not None:
            setattr(news, key, value.value)
        else:
            setattr(news, key, value)
    db.commit()
    db.refresh(news)
    return news


@router.delete("/{news_id}")
def delete_news(
    news_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    news = db.query(News).filter(News.id == news_id).first()
    if not news:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    write_audit(db, actor_id=current_user.id, action="DELETE_NEWS",
                entity="News", entity_id=news_id,
                old_value={"title": news.title})
    db.delete(news)
    db.commit()
    return {"message": "Новость удалена"}

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.models.news import NewsType


class NewsBase(BaseModel):
    title: str
    content: str
    type: NewsType = NewsType.general
    image_url: Optional[str] = None
    target_audience: str = "all"
    pinned: bool = False


class NewsCreate(NewsBase):
    pass


class NewsUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    type: Optional[NewsType] = None
    image_url: Optional[str] = None
    target_audience: Optional[str] = None
    pinned: Optional[bool] = None


class NewsResponse(NewsBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    created_by: Optional[UUID] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


class NewsReadResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    news_id: UUID
    user_id: UUID
    read_at: datetime


class NewsReadStats(BaseModel):
    total_employees: int
    read_count: int
    unread_count: int

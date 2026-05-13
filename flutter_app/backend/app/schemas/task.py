from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.models.task import TaskPriority, TaskStatus


class TaskBase(BaseModel):
    title: str
    description: Optional[str] = None
    assignee_id: UUID
    priority: TaskPriority = TaskPriority.medium
    due_date: Optional[date] = None


class TaskCreate(TaskBase):
    pass


class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[TaskStatus] = None
    priority: Optional[TaskPriority] = None
    due_date: Optional[date] = None
    blocker_reason: Optional[str] = None


class TaskResponse(TaskBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    assigner_id: UUID
    status: TaskStatus
    completed_at: Optional[datetime] = None
    blocker_reason: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

from datetime import datetime, timezone
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, UserStatus
from app.models.task import Task, TaskStatus, TaskPriority
from app.schemas.task import TaskCreate, TaskUpdate, TaskResponse
from app.utils.dependencies import get_current_user, require_admin, require_admin_or_teamlead

router = APIRouter(prefix="/tasks", tags=["Задачи"])


def _can_assign_task(current_user: User, assignee: User) -> bool:
    if current_user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN):
        return True
    if current_user.role == UserRole.TEAM_LEAD:
        return True
    return False


def _can_view_task(user: User, task: Task) -> bool:
    if user.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN, UserRole.TEAM_LEAD):
        return True
    return task.assignee_id == user.id


@router.get("", response_model=List[TaskResponse])
def list_tasks(
    assignee_id: Optional[UUID] = Query(None),
    status: Optional[TaskStatus] = Query(None),
    priority: Optional[TaskPriority] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Task)

    if assignee_id:
        query = query.filter(Task.assignee_id == assignee_id)
    if status:
        query = query.filter(Task.status == status)
    if priority:
        query = query.filter(Task.priority == priority)

    if current_user.role not in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    ):
        query = query.filter(Task.assignee_id == current_user.id)

    tasks = (
        query.order_by(Task.due_date.asc(), Task.priority.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )
    return tasks


@router.post("", response_model=TaskResponse, status_code=201)
def create_task(
    data: TaskCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    assignee = (
        db.query(User)
        .filter(User.id == data.assignee_id, User.deleted_at.is_(None))
        .first()
    )
    if not assignee or assignee.status != UserStatus.ACTIVE:
        raise HTTPException(status_code=404, detail="Исполнитель не найден")

    if not _can_assign_task(current_user, assignee):
        raise HTTPException(status_code=403, detail="Нет прав назначать задачи")

    task = Task(
        title=data.title,
        description=data.description,
        assigner_id=current_user.id,
        assignee_id=data.assignee_id,
        priority=data.priority,
        due_date=data.due_date,
        status=TaskStatus.todo,
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@router.get("/{task_id}", response_model=TaskResponse)
def get_task(
    task_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Задача не найдена")
    if not _can_view_task(current_user, task):
        raise HTTPException(status_code=403, detail="Доступ запрещён")
    return task


@router.patch("/{task_id}", response_model=TaskResponse)
def update_task(
    task_id: UUID,
    data: TaskUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Задача не найдена")
    if not _can_view_task(current_user, task):
        raise HTTPException(status_code=403, detail="Доступ запрещён")

    is_assignee = task.assignee_id == current_user.id
    is_assigner = task.assigner_id == current_user.id
    is_admin = current_user.role in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    )

    if not is_assigner and not is_admin:
        update_data = data.model_dump(exclude_none=True)
        allowed_fields = {"status", "blocker_reason"}
        update_data = {k: v for k, v in update_data.items() if k in allowed_fields}
    else:
        update_data = data.model_dump(exclude_none=True)

    if "status" in update_data and update_data["status"] == TaskStatus.done:
        task.completed_at = datetime.now(timezone.utc)
    elif "status" in update_data and update_data["status"] == TaskStatus.todo:
        task.completed_at = None

    for key, value in update_data.items():
        setattr(task, key, value)

    db.commit()
    db.refresh(task)
    return task


@router.delete("/{task_id}")
def delete_task(
    task_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Задача не найдена")
    if task.assigner_id != current_user.id and current_user.role not in (
        UserRole.ADMIN,
        UserRole.SUPER_ADMIN,
        UserRole.TEAM_LEAD,
    ):
        raise HTTPException(status_code=403, detail="Нет прав удалить задачу")
    db.delete(task)
    db.commit()
    return {"message": "Задача удалена"}

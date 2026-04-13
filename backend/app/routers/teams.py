"""
Команды/группы. Admin создаёт команду, назначает ментора и участников.
"""
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.team import Team
from app.models.user import User, UserRole, UserStatus
from app.utils.audit import write_audit
from app.utils.dependencies import get_current_user, require_admin

router = APIRouter(prefix="/teams", tags=["Команды"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class TeamMemberInfo(BaseModel):
    id: UUID
    full_name: str
    role: UserRole
    status: UserStatus
    avatar_url: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class TeamResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str] = None
    mentor_id: Optional[UUID] = None
    mentor_name: Optional[str] = None
    member_count: int = 0
    model_config = ConfigDict(from_attributes=True)


class TeamDetailResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str] = None
    mentor_id: Optional[UUID] = None
    mentor_name: Optional[str] = None
    members: List[TeamMemberInfo] = []
    model_config = ConfigDict(from_attributes=True)


class TeamCreateRequest(BaseModel):
    name: str
    description: Optional[str] = None
    mentor_id: Optional[UUID] = None


class TeamUpdateRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    mentor_id: Optional[UUID] = None


class AssignMembersRequest(BaseModel):
    user_ids: List[UUID]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_team_or_404(db: Session, team_id: UUID) -> Team:
    team = db.query(Team).filter(Team.id == team_id).first()
    if not team:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Команда не найдена")
    return team


def _serialize_team(team: Team) -> TeamResponse:
    mentor_name = team.mentor.full_name if team.mentor else None
    member_count = team.members.count() if team.members is not None else 0
    return TeamResponse(
        id=team.id,
        name=team.name,
        description=team.description,
        mentor_id=team.mentor_id,
        mentor_name=mentor_name,
        member_count=member_count,
    )


def _serialize_team_detail(team: Team) -> TeamDetailResponse:
    mentor_name = team.mentor.full_name if team.mentor else None
    members = [
        TeamMemberInfo(
            id=m.id,
            full_name=m.full_name,
            role=m.role,
            status=m.status,
            avatar_url=m.avatar_url,
        )
        for m in team.members
        if m.deleted_at is None
    ]
    return TeamDetailResponse(
        id=team.id,
        name=team.name,
        description=team.description,
        mentor_id=team.mentor_id,
        mentor_name=mentor_name,
        members=members,
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("", response_model=List[TeamResponse])
def list_teams(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Список всех команд. Доступно всем активным пользователям."""
    teams = db.query(Team).order_by(Team.name).all()
    return [_serialize_team(t) for t in teams]


@router.post("", response_model=TeamDetailResponse, status_code=status.HTTP_201_CREATED)
def create_team(
    data: TeamCreateRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Создать команду. Только Admin."""
    if db.query(Team).filter(Team.name == data.name).first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Команда с таким названием уже существует")

    if data.mentor_id:
        mentor = db.query(User).filter(User.id == data.mentor_id, User.deleted_at.is_(None)).first()
        if not mentor:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Ментор не найден")

    team = Team(name=data.name, description=data.description, mentor_id=data.mentor_id)
    db.add(team)
    db.flush()

    write_audit(
        db,
        actor_id=current_user.id,
        action="CREATE_TEAM",
        entity="Team",
        entity_id=team.id,
        old_value=None,
        new_value={"name": team.name, "mentor_id": str(team.mentor_id) if team.mentor_id else None},
        request=request,
    )
    db.commit()
    db.refresh(team)
    return _serialize_team_detail(team)


@router.get("/{team_id}", response_model=TeamDetailResponse)
def get_team(
    team_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Детали команды с участниками."""
    team = _get_team_or_404(db, team_id)
    return _serialize_team_detail(team)


@router.put("/{team_id}", response_model=TeamDetailResponse)
def update_team(
    team_id: UUID,
    data: TeamUpdateRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Обновить название / описание / ментора команды. Только Admin."""
    team = _get_team_or_404(db, team_id)

    if data.name and data.name != team.name:
        if db.query(Team).filter(Team.name == data.name, Team.id != team_id).first():
            raise HTTPException(status.HTTP_409_CONFLICT, detail="Команда с таким названием уже существует")

    if data.mentor_id is not None:
        mentor = db.query(User).filter(User.id == data.mentor_id, User.deleted_at.is_(None)).first()
        if not mentor:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Ментор не найден")

    old_val = {"name": team.name, "mentor_id": str(team.mentor_id) if team.mentor_id else None}
    patch = data.model_dump(exclude_unset=True)
    for field, value in patch.items():
        setattr(team, field, value)

    write_audit(
        db,
        actor_id=current_user.id,
        action="UPDATE_TEAM",
        entity="Team",
        entity_id=team.id,
        old_value=old_val,
        new_value={"name": team.name, "mentor_id": str(team.mentor_id) if team.mentor_id else None},
        request=request,
    )
    db.commit()
    db.refresh(team)
    return _serialize_team_detail(team)


@router.delete("/{team_id}", status_code=status.HTTP_200_OK)
def delete_team(
    team_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Удалить команду. Участники команды теряют team_id. Только Admin."""
    team = _get_team_or_404(db, team_id)

    # Unlink members
    db.query(User).filter(User.team_id == team_id).update(
        {"team_id": None, "team_name": None}, synchronize_session=False
    )

    write_audit(
        db,
        actor_id=current_user.id,
        action="DELETE_TEAM",
        entity="Team",
        entity_id=team.id,
        old_value={"name": team.name},
        new_value=None,
        request=request,
    )
    db.delete(team)
    db.commit()
    return {"message": f"Команда «{team.name}» удалена"}


@router.post("/{team_id}/members", response_model=TeamDetailResponse)
def assign_members(
    team_id: UUID,
    data: AssignMembersRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """
    Назначить участников команды (полная замена списка участников).
    Пользователи из предыдущего списка, не вошедшие в новый, получают team_id=None.
    Только Admin.
    """
    team = _get_team_or_404(db, team_id)

    # Detach old members
    db.query(User).filter(User.team_id == team_id).update(
        {"team_id": None, "team_name": None}, synchronize_session=False
    )

    # Attach new members
    if data.user_ids:
        users = db.query(User).filter(
            User.id.in_(data.user_ids),
            User.deleted_at.is_(None),
        ).all()
        if len(users) != len(data.user_ids):
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Один или несколько пользователей не найдены")
        for u in users:
            u.team_id = team_id
            u.team_name = team.name

    write_audit(
        db,
        actor_id=current_user.id,
        action="ASSIGN_TEAM_MEMBERS",
        entity="Team",
        entity_id=team.id,
        old_value=None,
        new_value={"user_ids": [str(uid) for uid in data.user_ids]},
        request=request,
    )
    db.commit()
    db.refresh(team)
    return _serialize_team_detail(team)


@router.delete("/{team_id}/members/{user_id}", status_code=status.HTTP_200_OK)
def remove_member(
    team_id: UUID,
    user_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Удалить одного участника из команды. Только Admin."""
    team = _get_team_or_404(db, team_id)
    user = db.query(User).filter(User.id == user_id, User.team_id == team_id).first()
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не состоит в этой команде")

    user.team_id = None
    user.team_name = None
    write_audit(
        db,
        actor_id=current_user.id,
        action="REMOVE_TEAM_MEMBER",
        entity="Team",
        entity_id=team.id,
        old_value={"user_id": str(user_id)},
        new_value=None,
        request=request,
    )
    db.commit()
    return {"message": f"{user.full_name} удалён из команды «{team.name}»"}


@router.get("/my/team", response_model=TeamDetailResponse)
def my_team(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Моя команда — для сотрудника/стажёра, чтобы видеть свою группу."""
    if not current_user.team_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Вы не состоите ни в одной команде")
    team = _get_team_or_404(db, current_user.team_id)
    return _serialize_team_detail(team)

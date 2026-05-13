from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models.office_network import OfficeNetwork, QRToken
from app.models.user import User
from app.schemas.office_network import OfficeNetworkCreate, OfficeNetworkResponse
from app.utils.dependencies import get_current_user, require_admin, require_admin_or_teamlead
from app.utils.audit import write_audit
from app.services.qr_service import generate_qr_token, generate_qr_image_base64, get_active_qr_token

# Office Networks Router
networks_router = APIRouter(prefix="/office-networks", tags=["Офисные сети"])


@networks_router.get("", response_model=List[OfficeNetworkResponse])
def list_networks(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    return db.query(OfficeNetwork).all()


@networks_router.post("", response_model=OfficeNetworkResponse, status_code=201)
def create_network(
    data: OfficeNetworkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    network = OfficeNetwork(**data.model_dump())
    db.add(network)
    db.commit()
    db.refresh(network)
    return network


@networks_router.put("/{network_id}", response_model=OfficeNetworkResponse)
def update_network(
    network_id: int,
    data: OfficeNetworkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    network = db.query(OfficeNetwork).filter(OfficeNetwork.id == network_id).first()
    if not network:
        raise HTTPException(status_code=404, detail="Сеть не найдена")
    for field, value in data.model_dump(exclude_none=True).items():
        setattr(network, field, value)
    db.commit()
    db.refresh(network)
    return network


@networks_router.patch("/{network_id}/activate")
def activate_network(
    network_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    network = db.query(OfficeNetwork).filter(OfficeNetwork.id == network_id).first()
    if not network:
        raise HTTPException(status_code=404, detail="Сеть не найдена")
    network.is_active = True
    write_audit(
        db,
        actor_id=current_user.id,
        action="ACTIVATE_OFFICE_NETWORK",
        entity="OfficeNetwork",
        new_value={"id": network.id, "name": network.name},
    )
    db.commit()
    return {"message": "Сеть активирована"}


@networks_router.patch("/{network_id}/deactivate")
def deactivate_network(
    network_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    network = db.query(OfficeNetwork).filter(OfficeNetwork.id == network_id).first()
    if not network:
        raise HTTPException(status_code=404, detail="Сеть не найдена")
    network.is_active = False
    write_audit(
        db,
        actor_id=current_user.id,
        action="DEACTIVATE_OFFICE_NETWORK",
        entity="OfficeNetwork",
        new_value={"id": network.id, "name": network.name},
    )
    db.commit()
    return {"message": "Сеть деактивирована"}


@networks_router.delete("/{network_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_network(
    network_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Полное удаление сети (ТЗ: конфигурация офисных сетей)."""
    network = db.query(OfficeNetwork).filter(OfficeNetwork.id == network_id).first()
    if not network:
        raise HTTPException(status_code=404, detail="Сеть не найдена")
    nid, nname = network.id, network.name
    write_audit(
        db,
        actor_id=current_user.id,
        action="DELETE_OFFICE_NETWORK",
        entity="OfficeNetwork",
        old_value={"id": nid, "name": nname},
    )
    db.delete(network)
    db.commit()
    return None


# QR Router
qr_router = APIRouter(prefix="/qr", tags=["QR-коды"])


@qr_router.get("")
def list_qr_tokens(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_teamlead),
):
    rows = db.query(QRToken).order_by(QRToken.created_at.desc()).all()
    return [
        {
            "id": r.id,
            "token": r.token,
            "type": r.type,
            "is_active": r.is_active,
            "expires_at": r.expires_at,
            "created_at": r.created_at,
        }
        for r in rows
    ]


@qr_router.get("/current")
def get_current_qr(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    qr = get_active_qr_token(db)
    if not qr:
        raise HTTPException(status_code=404, detail="Активный QR-код не найден")
    image = generate_qr_image_base64(qr.token)
    return {
        "token": qr.token,
        "type": qr.type,
        "image_base64": image,
        "created_at": qr.created_at
    }


@qr_router.post("/generate")
def generate_qr(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    # Deactivate all previous tokens
    db.query(QRToken).filter(QRToken.is_active == True).update({"is_active": False})
    db.commit()

    qr = generate_qr_token(db, token_type="attendance")
    image = generate_qr_image_base64(qr.token)
    write_audit(db, actor_id=current_user.id, action="GENERATE_QR",
                entity="QRToken", entity_id=qr.id,
                new_value={"type": qr.type})
    return {
        "token": qr.token,
        "type": qr.type,
        "image_base64": image,
        "created_at": qr.created_at
    }


@qr_router.post("/verify")
def verify_qr(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.services.qr_service import validate_qr_token

    valid, msg = validate_qr_token(token, db)
    return {"valid": valid, "message": msg}


@qr_router.patch("/{token_id}/activate")
def activate_qr_token(
    token_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Сделать выбранный QR активным (остальные деактивируются)."""
    qr = db.query(QRToken).filter(QRToken.id == token_id).first()
    if not qr:
        raise HTTPException(status_code=404, detail="QR-токен не найден")
    db.query(QRToken).filter(QRToken.is_active.is_(True), QRToken.id != token_id).update(
        {"is_active": False}, synchronize_session=False
    )
    qr.is_active = True
    write_audit(
        db,
        actor_id=current_user.id,
        action="ACTIVATE_QR_TOKEN",
        entity="QRToken",
        new_value={"id": qr.id, "type": qr.type},
    )
    db.commit()
    db.refresh(qr)
    return {"message": "QR активирован", "id": qr.id, "is_active": True}


@qr_router.patch("/{token_id}/deactivate")
def deactivate_qr_token(
    token_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    qr = db.query(QRToken).filter(QRToken.id == token_id).first()
    if not qr:
        raise HTTPException(status_code=404, detail="QR-токен не найден")
    qr.is_active = False
    write_audit(
        db,
        actor_id=current_user.id,
        action="DEACTIVATE_QR_TOKEN",
        entity="QRToken",
        new_value={"id": qr.id, "type": qr.type},
    )
    db.commit()
    return {"message": "QR деактивирован", "id": qr.id, "is_active": False}


@qr_router.delete("/{token_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_qr_token(
    token_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    qr = db.query(QRToken).filter(QRToken.id == token_id).first()
    if not qr:
        raise HTTPException(status_code=404, detail="QR-токен не найден")
    tid, ttype = qr.id, qr.type
    write_audit(
        db,
        actor_id=current_user.id,
        action="DELETE_QR_TOKEN",
        entity="QRToken",
        old_value={"id": tid, "type": ttype},
    )
    db.delete(qr)
    db.commit()
    return None
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models.office_network import OfficeNetwork, QRToken
from app.models.user import User
from app.schemas.attendance import OfficeNetworkCreate, OfficeNetworkResponse
from app.utils.dependencies import get_current_user, require_admin
from app.services.qr_service import (
    generate_qr_token,
    generate_qr_image_base64,
    get_active_qr_token,
)

# Office Networks Router
networks_router = APIRouter(prefix="/office-networks", tags=["Офисные сети"])


@networks_router.get("", response_model=List[OfficeNetworkResponse])
def list_networks(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    return db.query(OfficeNetwork).order_by(OfficeNetwork.id.desc()).all()


@networks_router.get("/{network_id}", response_model=OfficeNetworkResponse)
def get_network(
    network_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    network = db.query(OfficeNetwork).filter(OfficeNetwork.id == network_id).first()
    if not network:
        raise HTTPException(status_code=404, detail="Сеть не найдена")
    return network


@networks_router.post("", response_model=OfficeNetworkResponse, status_code=201)
def create_network(
    data: OfficeNetworkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    duplicate_name = db.query(OfficeNetwork).filter(OfficeNetwork.name == data.name).first()
    if duplicate_name:
        raise HTTPException(status_code=400, detail="Сеть с таким названием уже существует")

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

    duplicate_name = db.query(OfficeNetwork).filter(
        OfficeNetwork.name == data.name,
        OfficeNetwork.id != network_id
    ).first()
    if duplicate_name:
        raise HTTPException(status_code=400, detail="Сеть с таким названием уже существует")

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
    db.commit()
    return {"message": "Сеть деактивирована"}


@networks_router.delete("/{network_id}")
def delete_network(
    network_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    network = db.query(OfficeNetwork).filter(OfficeNetwork.id == network_id).first()
    if not network:
        raise HTTPException(status_code=404, detail="Сеть не найдена")

    db.delete(network)
    db.commit()
    return {"message": "Сеть удалена"}


# QR Router
qr_router = APIRouter(prefix="/qr", tags=["QR-коды"])


@qr_router.get("/current")
def get_current_qr(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    qr = get_active_qr_token(db)
    if not qr:
        raise HTTPException(status_code=404, detail="Активный QR-код не найден")

    image = generate_qr_image_base64(qr.token)
    return {
        "id": qr.id,
        "token": qr.token,
        "type": qr.type,
        "is_active": qr.is_active,
        "expires_at": qr.expires_at,
        "image_base64": image,
        "created_at": qr.created_at,
    }


@qr_router.get("")
def list_qr_codes(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    qrs = db.query(QRToken).order_by(QRToken.id.desc()).all()
    return [
        {
            "id": qr.id,
            "token": qr.token,
            "type": qr.type,
            "is_active": qr.is_active,
            "expires_at": qr.expires_at,
            "created_at": qr.created_at,
        }
        for qr in qrs
    ]


@qr_router.post("/generate")
def generate_qr(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    # Деактивируем текущие активные QR, но не удаляем их из истории
    db.query(QRToken).filter(QRToken.is_active == True).update({"is_active": False})
    db.commit()

    qr = generate_qr_token(db)
    image = generate_qr_image_base64(qr.token)

    return {
        "id": qr.id,
        "token": qr.token,
        "type": qr.type,
        "is_active": qr.is_active,
        "expires_at": qr.expires_at,
        "image_base64": image,
        "created_at": qr.created_at,
    }


@qr_router.patch("/{qr_id}/activate")
def activate_qr(
    qr_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    qr = db.query(QRToken).filter(QRToken.id == qr_id).first()
    if not qr:
        raise HTTPException(status_code=404, detail="QR-код не найден")

    # Только один QR должен быть активным одновременно
    db.query(QRToken).filter(QRToken.is_active == True).update({"is_active": False})
    qr.is_active = True
    db.commit()

    return {"message": "QR-код активирован"}


@qr_router.patch("/{qr_id}/deactivate")
def deactivate_qr(
    qr_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    qr = db.query(QRToken).filter(QRToken.id == qr_id).first()
    if not qr:
        raise HTTPException(status_code=404, detail="QR-код не найден")

    qr.is_active = False
    db.commit()

    return {"message": "QR-код деактивирован"}


@qr_router.delete("/{qr_id}")
def delete_qr(
    qr_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    qr = db.query(QRToken).filter(QRToken.id == qr_id).first()
    if not qr:
        raise HTTPException(status_code=404, detail="QR-код не найден")

    db.delete(qr)
    db.commit()

    return {"message": "QR-код удалён"}


@qr_router.post("/verify")
def verify_qr(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.services.qr_service import validate_qr_token

    valid, msg = validate_qr_token(token, db)
    return {"valid": valid, "message": msg}
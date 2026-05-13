import ipaddress
import logging
from typing import Optional, Tuple

from fastapi import Request
from sqlalchemy.orm import Session

from app.models.office_network import OfficeNetwork

logger = logging.getLogger(__name__)


def get_client_ip(request: Request) -> str:
    x_forwarded_for = request.headers.get("X-Forwarded-For")
    x_real_ip = request.headers.get("X-Real-IP")
    client_host = request.client.host if request.client else None

    if x_forwarded_for:
        return x_forwarded_for.split(",")[0].strip()

    if x_real_ip:
        return x_real_ip.strip()

    return client_host or ""


def is_ip_in_range(ip_str: str, ip_range: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str.strip())
        network = ipaddress.ip_network(ip_range.strip(), strict=False)
        return ip in network
    except ValueError:
        return False


def validate_office_network(ip_address: str, db: Session) -> Tuple[bool, Optional[OfficeNetwork]]:
    # localhost для локальной разработки
    if ip_address in ("127.0.0.1", "::1", "localhost"):
        dev_network = OfficeNetwork(id=0, name="Development", public_ip="127.0.0.1")
        return True, dev_network

    # временно разрешаем Docker-сеть на Mac
    if is_ip_in_range(ip_address, "192.168.65.0/24"):
        dev_network = OfficeNetwork(id=0, name="Docker Development", public_ip="192.168.65.1")
        return True, dev_network

    networks = db.query(OfficeNetwork).filter(OfficeNetwork.is_active == True).all()

    logger.debug("Validating IP=%s against %d active networks", ip_address, len(networks))

    for network in networks:
        if network.public_ip and network.public_ip.strip() == ip_address.strip():
            logger.debug("Matched by public_ip: network=%s", network.name)
            return True, network

        if network.ip_range and is_ip_in_range(ip_address, network.ip_range):
            logger.debug("Matched by ip_range: network=%s", network.name)
            return True, network

    logger.debug("No office network matched for IP=%s", ip_address)
    return False, None

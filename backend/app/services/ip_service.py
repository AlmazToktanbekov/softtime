import ipaddress
from typing import Optional, Tuple

from fastapi import Request
from sqlalchemy.orm import Session

from app.models.office_network import OfficeNetwork


def get_client_ip(request: Request) -> str:
    x_forwarded_for = request.headers.get("X-Forwarded-For")
    x_real_ip = request.headers.get("X-Real-IP")
    client_host = request.client.host if request.client else None

    print("DEBUG X-Forwarded-For =", x_forwarded_for)
    print("DEBUG X-Real-IP       =", x_real_ip)
    print("DEBUG request.client  =", client_host)

    if x_forwarded_for:
        real_ip = x_forwarded_for.split(",")[0].strip()
        print("DEBUG chosen IP from X-Forwarded-For =", real_ip)
        return real_ip

    if x_real_ip:
        real_ip = x_real_ip.strip()
        print("DEBUG chosen IP from X-Real-IP =", real_ip)
        return real_ip

    print("DEBUG chosen IP from request.client.host =", client_host)
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

    print("DEBUG validating IP =", ip_address)
    print("DEBUG active networks count =", len(networks))

    for network in networks:
        print(
            "DEBUG checking network:",
            {
                "id": network.id,
                "name": network.name,
                "public_ip": network.public_ip,
                "ip_range": network.ip_range,
                "is_active": network.is_active,
            }
        )

        if network.public_ip and network.public_ip.strip() == ip_address.strip():
            print("DEBUG matched by public_ip")
            return True, network

        if network.ip_range and is_ip_in_range(ip_address, network.ip_range):
            print("DEBUG matched by ip_range")
            return True, network

    print("DEBUG no office network matched")
    return False, None
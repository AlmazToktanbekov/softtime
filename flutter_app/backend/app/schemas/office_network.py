from typing import Optional
from pydantic import BaseModel, ConfigDict


class OfficeNetworkCreate(BaseModel):
    name: str
    public_ip: Optional[str] = None
    ip_range: Optional[str] = None
    description: Optional[str] = None


class OfficeNetworkResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    public_ip: Optional[str] = None
    ip_range: Optional[str] = None
    description: Optional[str] = None
    is_active: bool

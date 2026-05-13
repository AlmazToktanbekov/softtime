from pydantic import BaseModel, ConfigDict


class WorkSettingsUpdate(BaseModel):
    work_start_hour: int
    work_start_minute: int
    work_end_hour: int
    work_end_minute: int
    grace_period_minutes: int
    count_early_arrival: bool = True
    count_early_leave: bool = True
    count_overtime: bool = True


class WorkSettingsResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    work_start_hour: int
    work_start_minute: int
    work_end_hour: int
    work_end_minute: int
    grace_period_minutes: int
    count_early_arrival: bool
    count_early_leave: bool
    count_overtime: bool
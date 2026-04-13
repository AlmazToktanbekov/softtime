from datetime import datetime, time
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator, model_validator

_MIN_WORK_MINUTES = 6 * 60  # 360 minutes


def _validate_min_hours(start: Optional[time], end: Optional[time]) -> None:
    """Raise ValueError if end - start < 6 hours."""
    if start is None or end is None:
        return
    start_min = start.hour * 60 + start.minute
    end_min = end.hour * 60 + end.minute
    if end_min - start_min < _MIN_WORK_MINUTES:
        raise ValueError("Рабочий день не может быть менее 6 часов")


# ── Input: one day ────────────────────────────────────────────────────────────

class ScheduleDayInput(BaseModel):
    day_of_week: int
    is_working_day: bool = True
    start_time: Optional[time] = None
    end_time: Optional[time] = None

    @field_validator("day_of_week")
    @classmethod
    def day_range(cls, v: int) -> int:
        if not 0 <= v <= 6:
            raise ValueError("day_of_week должен быть от 0 (Пн) до 6 (Вс)")
        return v

    @model_validator(mode="after")
    def check_working_day_fields(self):
        if self.is_working_day:
            if self.start_time is None or self.end_time is None:
                raise ValueError(
                    "Для рабочего дня обязательны start_time и end_time"
                )
            _validate_min_hours(self.start_time, self.end_time)
        return self


# ── Input: full week (PUT body) ───────────────────────────────────────────────

class ScheduleWeekInput(BaseModel):
    days: List[ScheduleDayInput]

    @field_validator("days")
    @classmethod
    def no_duplicate_days(cls, v: List[ScheduleDayInput]) -> List[ScheduleDayInput]:
        seen = set()
        for d in v:
            if d.day_of_week in seen:
                raise ValueError(
                    f"day_of_week={d.day_of_week} встречается несколько раз"
                )
            seen.add(d.day_of_week)
        return v


# ── Response: one day ─────────────────────────────────────────────────────────

class ScheduleDayResponse(BaseModel):
    id: UUID
    user_id: UUID
    day_of_week: int
    day_name: str
    is_working_day: bool
    start_time: Optional[time]
    end_time: Optional[time]
    duration_minutes: int
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True)


# ── Response: today ───────────────────────────────────────────────────────────

class TodayScheduleResponse(BaseModel):
    day_of_week: int
    day_name: str
    is_working_day: bool
    start_time: Optional[time]
    end_time: Optional[time]

    model_config = ConfigDict(from_attributes=True)


# ── CRUD для /employee-schedules (совместимо с роутером) ───────────────────────

class EmployeeScheduleCreate(BaseModel):
    day_of_week: int
    is_working_day: bool = True
    start_time: Optional[time] = None
    end_time: Optional[time] = None

    @field_validator("day_of_week")
    @classmethod
    def day_range(cls, v: int) -> int:
        if not 0 <= v <= 6:
            raise ValueError("day_of_week 0–6 (Пн–Вс)")
        return v


class EmployeeScheduleUpdate(BaseModel):
    day_of_week: Optional[int] = None
    is_working_day: Optional[bool] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None


class EmployeeScheduleResponse(BaseModel):
    id: UUID
    user_id: UUID
    day_of_week: int
    is_working_day: bool
    start_time: Optional[time]
    end_time: Optional[time]
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = ConfigDict(from_attributes=True)

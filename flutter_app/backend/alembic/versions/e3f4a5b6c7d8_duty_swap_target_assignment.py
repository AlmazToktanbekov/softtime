"""duty_swap_target_assignment

Revision ID: e3f4a5b6c7d8
Revises: c1a3f2e9d045
Create Date: 2026-04-13

Adds optional target_assignment_id for mutual duty swaps (exchange dates).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from alembic import op

revision: str = "e3f4a5b6c7d8"
down_revision: Union[str, None] = "c1a3f2e9d045"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "duty_swaps",
        sa.Column("target_assignment_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_duty_swaps_target_assignment_id",
        "duty_swaps",
        "duty_assignments",
        ["target_assignment_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_duty_swaps_target_assignment_id", "duty_swaps", type_="foreignkey")
    op.drop_column("duty_swaps", "target_assignment_id")

"""add_teams_duty_type_user_role_in_reg

Revision ID: c1a3f2e9d045
Revises: b82dc270095d
Create Date: 2026-04-12

Changes:
- Add teams table
- Add team_id FK to users
- Add duty_type enum + column to duty_assignments and duty_checklist_items
- Remove old unique constraint on duty_assignments.date
- Add new unique constraint on (date, duty_type)
- Add role selection support in registration (column already exists)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from alembic import op

revision: str = "c1a3f2e9d045"
down_revision: Union[str, None] = "b82dc270095d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Enum type names in PostgreSQL
DUTY_TYPE_ENUM = postgresql.ENUM("LUNCH", "CLEANING", name="dutytype", create_type=False)


def upgrade() -> None:
    # ── Create dutytype enum ────────────────────────────────────────────────
    op.execute("CREATE TYPE dutytype AS ENUM ('LUNCH', 'CLEANING')")

    # ── Create teams table ──────────────────────────────────────────────────
    op.create_table(
        "teams",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("mentor_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(["mentor_id"], ["users.id"], name="fk_teams_mentor_id"),
        sa.UniqueConstraint("name", name="uq_teams_name"),
    )

    # ── Add team_id to users ────────────────────────────────────────────────
    op.add_column(
        "users",
        sa.Column("team_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_users_team_id",
        "users",
        "teams",
        ["team_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_users_team_id", "users", ["team_id"])

    # ── Add duty_type to duty_assignments ────────────────────────────────────
    # 1. Add column with a default so existing rows are migrated
    op.add_column(
        "duty_assignments",
        sa.Column(
            "duty_type",
            DUTY_TYPE_ENUM,
            nullable=False,
            server_default="LUNCH",
        ),
    )

    # 2. Drop the old unique constraint on date alone
    # (constraint name may differ — use try/except approach via raw SQL)
    op.execute(
        """
        DO $$
        DECLARE
            _con text;
        BEGIN
            SELECT conname INTO _con
            FROM pg_constraint
            WHERE conrelid = 'duty_assignments'::regclass
              AND contype = 'u'
              AND array_length(conkey, 1) = 1
              AND conkey[1] = (
                  SELECT attnum FROM pg_attribute
                  WHERE attrelid = 'duty_assignments'::regclass
                    AND attname = 'date'
              );
            IF _con IS NOT NULL THEN
                EXECUTE 'ALTER TABLE duty_assignments DROP CONSTRAINT ' || quote_ident(_con);
            END IF;
        END$$;
        """
    )

    # 3. Add new unique constraint on (date, duty_type)
    op.create_unique_constraint(
        "uq_duty_assignment_date_type",
        "duty_assignments",
        ["date", "duty_type"],
    )

    # ── Add duty_type to duty_checklist_items ────────────────────────────────
    op.add_column(
        "duty_checklist_items",
        sa.Column("duty_type", DUTY_TYPE_ENUM, nullable=True),
    )


def downgrade() -> None:
    # ── Remove duty_type from duty_checklist_items ───────────────────────────
    op.drop_column("duty_checklist_items", "duty_type")

    # ── Restore duty_assignments ─────────────────────────────────────────────
    op.drop_constraint("uq_duty_assignment_date_type", "duty_assignments", type_="unique")
    op.drop_column("duty_assignments", "duty_type")
    op.create_unique_constraint("uq_duty_date", "duty_assignments", ["date"])

    # ── Remove team_id from users ────────────────────────────────────────────
    op.drop_index("ix_users_team_id", table_name="users")
    op.drop_constraint("fk_users_team_id", "users", type_="foreignkey")
    op.drop_column("users", "team_id")

    # ── Drop teams table ─────────────────────────────────────────────────────
    op.drop_table("teams")

    # ── Drop enum ────────────────────────────────────────────────────────────
    op.execute("DROP TYPE dutytype")

"""add extras tables

Revision ID: 0a1b2c3d4e5f
Revises: e3f4a5b6c7d8
Create Date: 2026-04-24
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0a1b2c3d4e5f"
down_revision: Union[str, None] = "e3f4a5b6c7d8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # intern_diaries
    op.create_table(
        "intern_diaries",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("intern_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("diary_date", sa.Date, nullable=False),
        sa.Column("learned_today", sa.Text, nullable=False),
        sa.Column("difficulties", sa.Text, nullable=True),
        sa.Column("plans_tomorrow", sa.Text, nullable=True),
        sa.Column("mood", sa.Integer, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # intern_evaluations
    op.create_table(
        "intern_evaluations",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("intern_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("mentor_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("eval_period", sa.String(20), nullable=False),
        sa.Column("motivation_score", sa.Integer, nullable=False),
        sa.Column("knowledge_score", sa.Integer, nullable=False),
        sa.Column("communication_score", sa.Integer, nullable=False),
        sa.Column("comment", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # rooms
    op.create_table(
        "rooms",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("capacity", sa.Integer, default=10),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, default=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # room_bookings
    op.create_table(
        "room_bookings",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("room_id", UUID(as_uuid=True), sa.ForeignKey("rooms.id"), nullable=False, index=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("booking_date", sa.Date, nullable=False),
        sa.Column("start_time", sa.String(5), nullable=False),
        sa.Column("end_time", sa.String(5), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # kudos
    op.create_table(
        "kudos",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("from_user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("to_user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("message", sa.Text, nullable=False),
        sa.Column("emoji", sa.String(10), default="🙌"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # user_points
    op.create_table(
        "user_points",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, unique=True, index=True),
        sa.Column("total_points", sa.Integer, default=0),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # point_transactions
    op.create_table(
        "point_transactions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_points_id", UUID(as_uuid=True), sa.ForeignKey("user_points.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("amount", sa.Integer, nullable=False),
        sa.Column("reason", sa.String(200), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # rewards
    op.create_table(
        "rewards",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("cost_points", sa.Integer, nullable=False),
        sa.Column("emoji", sa.String(10), default="🎁"),
        sa.Column("is_active", sa.Boolean, default=True),
        sa.Column("stock", sa.Integer, default=-1),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # reward_claims
    op.create_table(
        "reward_claims",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("reward_id", UUID(as_uuid=True), sa.ForeignKey("rewards.id"), nullable=False),
        sa.Column("status", sa.String(20), default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade():
    op.drop_table("reward_claims")
    op.drop_table("rewards")
    op.drop_table("point_transactions")
    op.drop_table("user_points")
    op.drop_table("kudos")
    op.drop_table("room_bookings")
    op.drop_table("rooms")
    op.drop_table("intern_evaluations")
    op.drop_table("intern_diaries")

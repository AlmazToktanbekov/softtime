"""initial_schema_uuid

Revision ID: b82dc270095d
Revises:
Create Date: 2026-04-06

Full initial schema:
- All PKs are UUID (except office_networks, qr_tokens, work_settings which keep Integer)
- User model merges old User + Employee tables
- AuditLog table added
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from alembic import op

revision: str = "b82dc270095d"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── users ──────────────────────────────────────────────────────────────
    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("full_name", sa.String(100), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("phone", sa.String(20), nullable=False),
        sa.Column("username", sa.String(30), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column(
            "role",
            sa.Enum("SUPER_ADMIN", "ADMIN", "TEAM_LEAD", "EMPLOYEE", "INTERN", name="userrole"),
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.Enum("PENDING", "ACTIVE", "LEAVE", "WARNING", "BLOCKED", "DELETED", name="userstatus"),
            nullable=False,
        ),
        sa.Column("team_name", sa.String(100), nullable=True),
        sa.Column("mentor_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("avatar_url", sa.String(500), nullable=True),
        sa.Column("fcm_token", sa.Text, nullable=True),
        sa.Column("hired_at", sa.Date, nullable=True),
        sa.Column("admin_comment", sa.Text, nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("email", name="uq_users_email"),
        sa.UniqueConstraint("phone", name="uq_users_phone"),
        sa.UniqueConstraint("username", name="uq_users_username"),
    )
    op.create_index("ix_users_id", "users", ["id"])
    op.create_index("ix_users_email", "users", ["email"])
    op.create_index("ix_users_username", "users", ["username"])

    # ── audit_logs ─────────────────────────────────────────────────────────
    op.create_table(
        "audit_logs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("action", sa.String(100), nullable=False),
        sa.Column("entity", sa.String(50), nullable=False),
        sa.Column("entity_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("old_value", postgresql.JSONB, nullable=True),
        sa.Column("new_value", postgresql.JSONB, nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_audit_logs_id", "audit_logs", ["id"])
    op.create_index("ix_audit_logs_user_id", "audit_logs", ["user_id"])

    # ── office_networks ────────────────────────────────────────────────────
    op.create_table(
        "office_networks",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("public_ip", sa.String(45), nullable=True),
        sa.Column("ip_range", sa.String(50), nullable=True),
        sa.Column("description", sa.String(255), nullable=True),
        sa.Column("is_active", sa.Boolean, default=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # ── qr_tokens ──────────────────────────────────────────────────────────
    op.create_table(
        "qr_tokens",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("token", sa.String(255), nullable=False),
        sa.Column("type", sa.String(50), default="static"),
        sa.Column("is_active", sa.Boolean, default=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("token", name="uq_qr_tokens_token"),
    )
    op.create_index("ix_qr_tokens_token", "qr_tokens", ["token"])

    # ── work_settings ──────────────────────────────────────────────────────
    op.create_table(
        "work_settings",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("work_start_hour", sa.Integer, nullable=False, default=9),
        sa.Column("work_start_minute", sa.Integer, nullable=False, default=0),
        sa.Column("work_end_hour", sa.Integer, nullable=False, default=18),
        sa.Column("work_end_minute", sa.Integer, nullable=False, default=0),
        sa.Column("grace_period_minutes", sa.Integer, nullable=False, default=10),
        sa.Column("count_early_arrival", sa.Boolean, nullable=False, default=True),
        sa.Column("count_early_leave", sa.Boolean, nullable=False, default=True),
        sa.Column("count_overtime", sa.Boolean, nullable=False, default=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
    )

    # ── employee_schedules ─────────────────────────────────────────────────
    op.create_table(
        "employee_schedules",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("day_of_week", sa.Integer, nullable=False),
        sa.Column("is_workday", sa.Boolean, nullable=False, default=True),
        sa.Column("start_time", sa.Time, nullable=True),
        sa.Column("end_time", sa.Time, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
        sa.UniqueConstraint("user_id", "day_of_week", name="uq_schedule_user_day"),
    )
    op.create_index("ix_employee_schedules_user_id", "employee_schedules", ["user_id"])

    # ── attendance ─────────────────────────────────────────────────────────
    op.create_table(
        "attendance",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("check_in_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "check_in_status",
            sa.Enum("ON_TIME", "LATE", "EARLY_ARRIVAL", name="checkinstatus"),
            nullable=True,
        ),
        sa.Column("check_in_ip", sa.String(45), nullable=True),
        sa.Column("qr_verified_in", sa.Boolean, default=False),
        sa.Column("check_out_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "check_out_status",
            sa.Enum("ON_TIME", "LEFT_EARLY", "OVERTIME", name="checkoutstatus"),
            nullable=True,
        ),
        sa.Column("check_out_ip", sa.String(45), nullable=True),
        sa.Column("qr_verified_out", sa.Boolean, default=False),
        sa.Column("late_minutes", sa.Integer, default=0),
        sa.Column("office_network_id", sa.Integer, sa.ForeignKey("office_networks.id"), nullable=True),
        sa.Column("note", sa.String(500), nullable=True),
        sa.Column("is_manual", sa.Boolean, default=False),
        sa.Column("manual_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
    )
    op.create_index("ix_attendance_user_id", "attendance", ["user_id"])
    op.create_index("ix_attendance_date", "attendance", ["date"])

    # ── attendance_logs ────────────────────────────────────────────────────
    op.create_table(
        "attendance_logs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("result", sa.String(50), nullable=False),
        sa.Column("message", sa.String(500), nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("user_agent", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_attendance_logs_user_id", "attendance_logs", ["user_id"])

    # ── absence_requests ───────────────────────────────────────────────────
    op.create_table(
        "absence_requests",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column(
            "request_type",
            sa.Enum(
                "sick", "family", "vacation", "business_trip",
                "remote_work", "late_reason", "early_leave", "other",
                name="absencerequesttype",
            ),
            nullable=False,
        ),
        sa.Column("start_date", sa.Date, nullable=False),
        sa.Column("end_date", sa.Date, nullable=True),
        sa.Column("start_time", sa.Time, nullable=True),
        sa.Column("comment_employee", sa.String(1000), nullable=True),
        sa.Column("comment_admin", sa.String(1000), nullable=True),
        sa.Column(
            "status",
            sa.Enum(
                "new", "reviewing", "approved", "rejected", "needs_clarification",
                name="absencerequeststatus",
            ),
            nullable=False,
        ),
        sa.Column("reviewed_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
    )
    op.create_index("ix_absence_requests_user_id", "absence_requests", ["user_id"])

    # ── duty_queue ─────────────────────────────────────────────────────────
    op.create_table(
        "duty_queue",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("queue_order", sa.Integer, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
        sa.UniqueConstraint("user_id", name="uq_duty_queue_user"),
        sa.UniqueConstraint("queue_order", name="uq_duty_queue_order"),
    )

    # ── duty_assignments ───────────────────────────────────────────────────
    op.create_table(
        "duty_assignments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("is_completed", sa.Boolean, nullable=False, default=False),
        sa.Column("completion_tasks", postgresql.JSONB, nullable=True),
        sa.Column("completion_qr_verified", sa.Boolean, nullable=False, default=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("verified", sa.Boolean, nullable=False, default=False),
        sa.Column("verified_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("admin_note", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
        sa.UniqueConstraint("date", name="uq_duty_assignments_date"),
    )
    op.create_index("ix_duty_assignments_user_id", "duty_assignments", ["user_id"])

    # ── duty_checklist_items ───────────────────────────────────────────────
    op.create_table(
        "duty_checklist_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("text", sa.String(500), nullable=False),
        sa.Column("order", sa.Integer, default=0),
        sa.Column("is_active", sa.Boolean, default=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # ── duty_swaps ─────────────────────────────────────────────────────────
    op.create_table(
        "duty_swaps",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("requester_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("assignment_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("duty_assignments.id"), nullable=False),
        sa.Column("status", sa.String(50), default="pending"),
        sa.Column("response_note", sa.Text, nullable=True),
        sa.Column("responded_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("responded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # ── news ───────────────────────────────────────────────────────────────
    op.create_table(
        "news",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("content", sa.Text, nullable=False),
        sa.Column("type", sa.String(50), default="general"),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("target_audience", sa.String(100), default="all"),
        sa.Column("pinned", sa.Boolean, nullable=False, default=False),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
    )

    # ── news_reads ─────────────────────────────────────────────────────────
    op.create_table(
        "news_reads",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("news_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("news.id"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_news_reads_news_id", "news_reads", ["news_id"])

    # ── tasks ──────────────────────────────────────────────────────────────
    op.create_table(
        "tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("assigner_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("assignee_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column(
            "status",
            sa.Enum("todo", "in_progress", "done", "blocked", name="taskstatus"),
            nullable=False,
        ),
        sa.Column(
            "priority",
            sa.Enum("low", "medium", "high", "critical", name="taskpriority"),
            nullable=False,
        ),
        sa.Column("due_date", sa.Date, nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("blocker_reason", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("tasks")
    op.drop_table("news_reads")
    op.drop_table("news")
    op.drop_table("duty_swaps")
    op.drop_table("duty_checklist_items")
    op.drop_table("duty_assignments")
    op.drop_table("duty_queue")
    op.drop_table("absence_requests")
    op.drop_table("attendance_logs")
    op.drop_table("attendance")
    op.drop_table("employee_schedules")
    op.drop_table("work_settings")
    op.drop_table("qr_tokens")
    op.drop_table("office_networks")
    op.drop_table("audit_logs")
    op.drop_table("users")

    op.execute("DROP TYPE IF EXISTS userrole")
    op.execute("DROP TYPE IF EXISTS userstatus")
    op.execute("DROP TYPE IF EXISTS checkinstatus")
    op.execute("DROP TYPE IF EXISTS checkoutstatus")
    op.execute("DROP TYPE IF EXISTS absencerequesttype")
    op.execute("DROP TYPE IF EXISTS absencerequeststatus")
    op.execute("DROP TYPE IF EXISTS taskstatus")
    op.execute("DROP TYPE IF EXISTS taskpriority")

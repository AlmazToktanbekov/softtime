"""add daily_report fields to attendance

Revision ID: f1a2b3c4d5e6
Revises: 0a1b2c3d4e5f
Create Date: 2026-05-08 17:28:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'f1a2b3c4d5e6'
down_revision = '0a1b2c3d4e5f'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('attendance', sa.Column('daily_report', sa.String(2000), nullable=True))
    op.add_column('attendance', sa.Column('daily_report_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('attendance', 'daily_report_at')
    op.drop_column('attendance', 'daily_report')

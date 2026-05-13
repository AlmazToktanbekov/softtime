from sqlalchemy import text
from app.database import engine

with engine.begin() as conn:
    try:
        conn.execute(text('ALTER TABLE attendance ADD COLUMN daily_report VARCHAR;'))
        print("Added daily_report")
    except Exception as e:
        print(e)
    try:
        conn.execute(text('ALTER TABLE attendance ADD COLUMN daily_report_at TIMESTAMP WITH TIME ZONE;'))
        print("Added daily_report_at")
    except Exception as e:
        print(e)

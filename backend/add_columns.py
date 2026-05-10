import sys
from sqlalchemy import create_engine, text

DATABASE_URL = "postgresql+psycopg2://softtime:softtime123@localhost:5432/softtime_db"
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    try:
        conn.execute(text("ALTER TABLE attendance ADD COLUMN daily_report VARCHAR(2000)"))
        print("Added daily_report column.")
    except Exception as e:
        print("daily_report column might already exist:", e)
        
    try:
        conn.execute(text("ALTER TABLE attendance ADD COLUMN daily_report_at TIMESTAMP WITH TIME ZONE"))
        print("Added daily_report_at column.")
    except Exception as e:
        print("daily_report_at column might already exist:", e)
    
    conn.commit()

print("Done.")

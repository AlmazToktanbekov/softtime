import sys
import os

sys.path.append(os.getcwd())

from app.database import SessionLocal
from app.models.user import User

def list_users():
    db = SessionLocal()
    try:
        users = db.query(User).all()
        print(f"Total users in DB: {len(users)}")
        for u in users:
            print(f"- Username: {u.username}, Email: {u.email}, Role: {u.role}, Status: {u.status}")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    list_users()

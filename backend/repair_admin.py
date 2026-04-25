import sys
import os

# Добавляем текущую директорию в пути поиска модулей
sys.path.append(os.getcwd())

from app.database import SessionLocal
from app.models.user import User, UserRole, UserStatus
from app.utils.security import get_password_hash
from app.config import settings

def repair():
    db = SessionLocal()
    try:
        username = settings.DEFAULT_ADMIN_USERNAME
        email = settings.DEFAULT_ADMIN_EMAIL
        password = settings.DEFAULT_ADMIN_PASSWORD
        
        print(f"Repairing user: {username}")
        
        user = db.query(User).filter(User.username == username).first()
        if not user:
            print("Admin not found, creating new one...")
            user = User(
                full_name="Super Admin",
                username=username,
                email=email,
                password_hash=get_password_hash(password),
                role=UserRole.SUPER_ADMIN,
                status=UserStatus.ACTIVE,
                phone="+99600000000"
            )
            db.add(user)
        else:
            print("Admin found, resetting password and status...")
            user.password_hash = get_password_hash(password)
            user.status = UserStatus.ACTIVE
            user.role = UserRole.SUPER_ADMIN
            if not user.email:
                user.email = email
        
        db.commit()
        print(f"Success! Login: {username}, Password: {password}")
        
    except Exception as e:
        print(f"Error: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    repair()

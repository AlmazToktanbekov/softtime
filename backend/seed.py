"""
Seed: админ, тестовые пользователи, офисная сеть, QR, чеклист дежурств, очередь, новость.
Запуск: cd backend && python seed.py
"""
import os
import secrets
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import date

from app.database import Base, SessionLocal, engine
from app.models.duty import DutyChecklistItem, DutyQueue
from app.models.news import News
from app.models.office_network import OfficeNetwork, QRToken
from app.models.user import User, UserRole, UserStatus
from app.utils.security import get_password_hash

Base.metadata.create_all(bind=engine)
db = SessionLocal()


def _ensure_user(
    username: str,
    email: str,
    phone: str,
    full_name: str,
    password: str,
    role: UserRole = UserRole.EMPLOYEE,
    status: UserStatus = UserStatus.ACTIVE,
) -> User:
    u = db.query(User).filter(User.username == username).first()
    if u:
        return u
    user = User(
        username=username,
        email=email,
        phone=phone,
        full_name=full_name,
        password_hash=get_password_hash(password),
        role=role,
        status=status,
        hired_at=date(2023, 1, 15),
    )
    db.add(user)
    db.flush()
    print(f"✅ Пользователь: {username} / {password}")
    return user


# Админ
if not db.query(User).filter(User.username == "admin").first():
    _ensure_user(
        "admin",
        "admin@company.com",
        "+996700000001",
        "Администратор",
        "admin123",
        role=UserRole.ADMIN,
        status=UserStatus.ACTIVE,
    )

# Тестовые сотрудники
samples = [
    ("Иванов Иван", "ivan.ivanov@company.com", "+996700100001", "ivan.ivanov", "pass123"),
    ("Петрова Мария", "maria.petrova@company.com", "+996700100002", "maria.petrova", "pass123"),
    ("Сидоров Алексей", "alexey.sidorov@company.com", "+996700100003", "alexey.sidorov", "pass123"),
]
for full_name, email, phone, username, pwd in samples:
    if not db.query(User).filter(User.email == email).first():
        _ensure_user(username, email, phone, full_name, pwd, UserRole.EMPLOYEE, UserStatus.ACTIVE)

# Офисная сеть
if not db.query(OfficeNetwork).first():
    net = OfficeNetwork(
        name="Главный офис",
        public_ip="127.0.0.1",
        ip_range="192.168.1.0/24",
        description="Dev / main",
    )
    db.add(net)
    print("✅ Офисная сеть добавлена")

# QR
if not db.query(QRToken).filter(QRToken.type == "attendance", QRToken.is_active == True).first():  # noqa: E712
    db.add(QRToken(token=secrets.token_urlsafe(32), type="attendance", is_active=True))
    print("✅ QR attendance")

if not db.query(QRToken).filter(QRToken.type == "duty", QRToken.is_active == True).first():  # noqa: E712
    db.add(QRToken(token=secrets.token_urlsafe(32), type="duty", is_active=True))
    print("✅ QR duty")

# Чеклист дежурств
default_checklist = [
    "Помыть посуду",
    "Протереть стол",
    "Вынести мусор",
    "Проверить чай/кофе",
    "Заказать обед (12:00)",
    "Убрать после обеда",
]
if not db.query(DutyChecklistItem).first():
    for idx, text in enumerate(default_checklist):
        db.add(DutyChecklistItem(text=text, order=idx, is_active=True))
    print("✅ Чеклист дежурств")

# Очередь дежурств — все активные пользователи (кроме админа по желанию)
users_for_queue = (
    db.query(User)
    .filter(
        User.deleted_at.is_(None),
        User.status == UserStatus.ACTIVE,
        User.role == UserRole.EMPLOYEE,
    )
    .order_by(User.created_at)
    .all()
)
if users_for_queue and not db.query(DutyQueue).first():
    for idx, u in enumerate(users_for_queue):
        db.add(DutyQueue(user_id=u.id, queue_order=idx))
    print(f"✅ Очередь дежурств: {len(users_for_queue)} чел.")

# Новость
if not db.query(News).first():
    admin_user = db.query(User).filter(User.username == "admin").first()
    db.add(
        News(
            title="Добро пожаловать в SoftTime",
            content="Корпоративные новости и объявления.",
            type="announcement",
            target_audience="all",
            pinned=True,
            created_by=admin_user.id if admin_user else None,
        )
    )
    print("✅ Пример новости")

db.commit()
db.close()
print("\n🎉 Seed завершён. Admin: admin / admin123")

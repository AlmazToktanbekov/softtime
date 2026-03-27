"""
Seed script: creates admin user, sample employees, QR token, and office network.
Run: python seed.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.database import engine, Base, SessionLocal
from app.models.user import User, UserRole
from app.models.employee import Employee
from app.models.office_network import OfficeNetwork, QRToken
from app.utils.security import get_password_hash
from datetime import date

Base.metadata.create_all(bind=engine)
db = SessionLocal()

# Admin user
if not db.query(User).filter(User.username == 'admin').first():
    admin = User(
        username='admin',
        email='admin@company.com',
        password_hash=get_password_hash('admin123'),
        role=UserRole.admin,
    )
    db.add(admin)
    db.flush()
    print("✅ Admin created: admin / admin123")

# Sample employees
samples = [
    ('Иванов Иван Иванович', 'ivan.ivanov@company.com', '+7 900 100 00 01', 'Разработка', 'Senior Developer', 'ivan.ivanov', 'pass123'),
    ('Петрова Мария Сергеевна', 'maria.petrova@company.com', '+7 900 100 00 02', 'Разработка', 'QA Engineer', 'maria.petrova', 'pass123'),
    ('Сидоров Алексей Николаевич', 'alexey.sidorov@company.com', '+7 900 100 00 03', 'Менеджмент', 'Project Manager', 'alexey.sidorov', 'pass123'),
    ('Козлова Анна Дмитриевна', 'anna.kozlova@company.com', '+7 900 100 00 04', 'HR', 'HR Manager', 'anna.kozlova', 'pass123'),
]

for full_name, email, phone, dept, pos, username, password in samples:
    if not db.query(Employee).filter(Employee.email == email).first():
        emp = Employee(full_name=full_name, email=email, phone=phone, department=dept, position=pos, hire_date=date(2023, 1, 15))
        db.add(emp); db.flush()
        user = User(
            username=username, email=email,
            password_hash=get_password_hash(password),
            role=UserRole.employee, employee_id=emp.id
        )
        db.add(user)
        print(f"✅ Employee: {full_name} / {username} / {password}")

# Office network
if not db.query(OfficeNetwork).first():
    net = OfficeNetwork(name='Главный офис', public_ip='127.0.0.1', ip_range='192.168.1.0/24', description='Development / Main Office')
    db.add(net)
    print("✅ Office network added")

# QR token
if not db.query(QRToken).filter(QRToken.is_active == True).first():
    import secrets
    qr = QRToken(token=secrets.token_urlsafe(32), type='static', is_active=True)
    db.add(qr)
    print(f"✅ QR token created")

db.commit()
db.close()
print("\n🎉 Seed complete!")
print("   Admin: admin / admin123")
print("   Employee: ivan.ivanov / pass123")

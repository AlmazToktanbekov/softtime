# SoftTime — Система управления офисом (Softjol)

Корпоративная система учёта посещаемости, дежурств, новостей и расписаний сотрудников.

## Стек

| Слой | Технология |
|------|-----------|
| Backend | FastAPI + SQLAlchemy + PostgreSQL + Redis + Alembic |
| Mobile | Flutter (Dart) |
| Admin Web | Статический SPA (HTML/CSS/JS) |
| Deploy | Docker Compose + Nginx |
| Push | FCM (Firebase Cloud Messaging) |

## Структура проекта

```
softtime/
├── backend/          # FastAPI REST API
├── flutter_app/      # Flutter мобильное приложение
├── admin_web/        # Веб-панель администратора
├── docs/             # Документация и ТЗ
├── nginx/            # Конфигурация Nginx
├── pictures/         # Логотипы и фирменные материалы
├── docker-compose.yml
└── .env.example
```

## Быстрый старт

### 1. Настройка переменных окружения

```bash
cp .env.example .env
# Отредактируйте .env — смените пароли и секреты
```

**Обязательно смените в `.env`:**
- `POSTGRES_PASSWORD`
- `SECRET_KEY` — генерировать: `python3 -c "import secrets; print(secrets.token_hex(32))"`
- `DEFAULT_ADMIN_PASSWORD`

### 2. Запуск через Docker Compose

```bash
docker compose up -d
```

Сервисы:
- **Backend API**: http://localhost:8000
- **Swagger UI**: http://localhost:8000/docs
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379

### 3. Применение миграций

```bash
docker compose exec backend alembic upgrade head
```

### 4. Запуск Flutter приложения

```bash
cd flutter_app
flutter pub get
flutter run
```

### 5. Admin Web панель

Открыть `admin_web/index.html` в браузере или настроить Nginx для раздачи.

---

## Роли пользователей

| Роль | Описание |
|------|---------|
| `SUPER_ADMIN` | Полный доступ, управляет Admin-ами |
| `ADMIN` | Управляет сотрудниками, дежурствами, расписанием |
| `TEAM_LEAD` | Видит свою группу + отчёты группы |
| `EMPLOYEE` | Стандартный сотрудник |
| `INTERN` | Стажёр (те же права, что у EMPLOYEE) |

---

## API Эндпоинты

Базовый путь: `/api/v1`

| Группа | Префикс | Описание |
|--------|---------|---------|
| Авторизация | `/auth` | Регистрация, вход, refresh, logout |
| Пользователи | `/users` | CRUD, статусы, аватары, approve/reject |
| Команды | `/teams` | Группы сотрудников |
| Посещаемость | `/attendance` | Check-in/out, история, ручные правки |
| Расписание | `/employee-schedules` | Индивидуальные графики |
| Дежурства | `/duty` | Очередь, назначения, чеклист, обмены |
| Новости | `/news` | Лента, read tracking |
| Заявки | `/absence-requests` | Отпуска и отсутствия |
| Отчёты | `/reports` | Аналитика посещаемости |
| Сети | `/office-networks` | IP-сети офиса |
| QR-коды | `/qr` | Генерация и управление QR |
| Аудит | `/audit-logs` | Лог действий Admin |
| Настройки | `/settings` | Глобальные параметры работы |

Полная документация: http://localhost:8000/docs

---

## Переменные окружения

| Переменная | Описание |
|-----------|---------|
| `POSTGRES_DB` | Имя базы данных |
| `POSTGRES_USER` | Пользователь PostgreSQL |
| `POSTGRES_PASSWORD` | Пароль PostgreSQL |
| `REDIS_URL` | URL Redis (например, `redis://redis:6379`) |
| `SECRET_KEY` | Секрет для подписи JWT |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Время жизни access token (по умолчанию: 15) |
| `REFRESH_TOKEN_EXPIRE_DAYS` | Время жизни refresh token (по умолчанию: 30) |
| `DEFAULT_ADMIN_USERNAME` | Логин первого Super Admin |
| `DEFAULT_ADMIN_EMAIL` | Email первого Super Admin |
| `DEFAULT_ADMIN_PASSWORD` | Пароль первого Super Admin |
| `AUTO_CREATE_TABLES` | Создавать таблицы при старте (dev only) |
| `DEBUG` | Режим отладки |

---

## Разработка

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Создать миграцию
alembic revision --autogenerate -m "description"

# Применить миграции
alembic upgrade head
```

### Полная документация

- [Техническое задание v2.0](CLAUDE.md)
- [Дизайн-спецификация](docs/design_spec.md)
- [Оригинальное ТЗ v1.0](docs/SoftTime_TZ_v1.0.md)

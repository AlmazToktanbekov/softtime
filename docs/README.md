# 📊 SoftTime — документация репозитория

Система учёта посещаемости и управления офисом (**Softjol / SoftTime**) на базе Flutter + FastAPI.

## Техническое задание

**Официальное ТЗ продукта (v1.0.0):** [SoftTime_TZ_v1.0.md](./SoftTime_TZ_v1.0.md) — цели, модули, роли, бизнес-правила, API (примеры в ТЗ; фактические пути — `/api/v1/...`).

---

## 🚀 Быстрый старт

### 1. Запуск backend с Docker

```bash
cd attendance_system
docker-compose up --build
```

Backend будет доступен на: `http://localhost:8000`
Swagger документация: `http://localhost:8000/docs`

### 1.1. Локальный запуск backend (без Docker)

Если вы хотите запускать backend напрямую на машине:

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

# Пример для локального Postgres:
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/attendance_db"
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

> По умолчанию таблицы создаются автоматически при старте (`AUTO_CREATE_TABLES=true`).

### 2. Инициализация данных

После запуска контейнеров:

```bash
docker-compose exec backend python seed.py
```

Создаст:
- Администратор: `admin` / `admin123`
- Сотрудники: `ivan.ivanov` / `pass123`, `maria.petrova` / `pass123`
- Офисную сеть (localhost + 192.168.1.0/24)
- Активный QR-токен

### 3. Веб-панель администратора

Откройте `admin_web/index.html` в браузере (или настройте Nginx для раздачи).

Войдите с `admin` / `admin123`

### 4. Flutter приложение

```bash
cd flutter_app
flutter pub get
flutter run
```

> Измените `lib/config/app_config.dart` → `baseUrl` под ваш сервер.

---

## 🏗️ Структура проекта

```
attendance_system/
├── backend/               # FastAPI backend
│   ├── app/
│   │   ├── main.py        # Точка входа
│   │   ├── config.py      # Настройки
│   │   ├── database.py    # База данных
│   │   ├── models/        # SQLAlchemy модели
│   │   ├── schemas/       # Pydantic схемы
│   │   ├── routers/       # API роутеры
│   │   ├── services/      # Бизнес-логика
│   │   └── utils/         # Утилиты
│   ├── seed.py            # Начальные данные
│   ├── Dockerfile
│   └── requirements.txt
│
├── flutter_app/           # Flutter мобильное приложение
│   ├── lib/
│   │   ├── main.dart
│   │   ├── config/        # Настройки (URL API)
│   │   ├── models/        # Модели данных
│   │   ├── services/      # API сервис + провайдеры
│   │   ├── screens/       # Экраны приложения
│   │   ├── widgets/       # Компоненты UI
│   │   └── theme/         # Тема и стили
│   └── pubspec.yaml
│
├── admin_web/             # Веб-панель администратора
│   └── index.html         # Single-page admin panel
│
├── nginx/
│   └── nginx.conf         # Nginx конфигурация
│
└── docker-compose.yml
```

---

## 📱 Экраны Flutter приложения

| Экран | Описание |
|-------|----------|
| Авторизация | Вход по логину/паролю |
| Главный экран | Статус дня, кнопки прихода/ухода |
| QR-сканер | Камера для сканирования QR-кода |
| История | Список посещений с фильтром по датам |
| Профиль | Данные сотрудника |
| Админ-панель | Управление (для администраторов) |

---

## 🔌 API Endpoints

### Аутентификация
```
POST /api/v1/auth/login       — Вход
POST /api/v1/auth/refresh     — Обновление токена
GET  /api/v1/auth/me          — Текущий пользователь
POST /api/v1/auth/logout      — Выход
```

### Сотрудники
```
GET    /api/v1/employees          — Список
POST   /api/v1/employees          — Создать
GET    /api/v1/employees/{id}     — Карточка
PUT    /api/v1/employees/{id}     — Обновить
PATCH  /api/v1/employees/{id}/deactivate — Деактивировать
```

### Посещаемость
```
POST  /api/v1/attendance/check-in         — Отметить приход
POST  /api/v1/attendance/check-out        — Отметить уход
GET   /api/v1/attendance/my               — Моя история
GET   /api/v1/attendance                  — Все записи (admin)
PATCH /api/v1/attendance/{id}/manual-update — Ручная правка
```

### Отчеты
```
GET /api/v1/reports/daily     — Дневной отчет
GET /api/v1/reports/weekly    — Недельный
GET /api/v1/reports/monthly   — Месячный
GET /api/v1/reports/department — По отделу
```

---

## ⚙️ Конфигурация (.env)

```env
DATABASE_URL=postgresql://postgres:postgres@db:5432/attendance_db
SECRET_KEY=your-secret-key
WORK_START_HOUR=9
WORK_START_MINUTE=0
GRACE_PERIOD_MINUTES=10
```

---

## 🔐 Логика проверки присутствия

Отметка принимается только при **одновременном** выполнении:
1. ✅ Сотрудник авторизован (JWT токен)
2. ✅ QR-код действителен (из базы данных)
3. ✅ IP-адрес запроса принадлежит офисной сети

---

## 📊 Статусы посещаемости

| Статус | Описание |
|--------|----------|
| `present` | Пришел вовремя |
| `late` | Опоздал (после grace period) |
| `absent` | Не отмечен |
| `incomplete` | Приход без ухода |
| `completed` | Приход + уход |
| `manual` | Скорректировано администратором |
| `approved_absence` | Разрешённое отсутствие (админ указал причину с комментарием) |

---

## ✓ Разрешённое отсутствие (админ)

Если сотрудник не пришёл по уважительной причине, администратор может указать **разрешённое отсутствие** с комментарием (больничный, отпуск, удалёнка и т.д.):

- **Веб-панель:** раздел «Посещаемость» → кнопка «Разрешённое отсутствие» → выбрать сотрудника, дату, ввести комментарий.
- **Flutter (админ):** вкладка «Посещаемость» → FAB «Разреш. отсутствие».
- **API:** `POST /api/v1/attendance/mark-approved-absence` (body: `employee_id`, `date`, `note`).

В отчётах такие сотрудники не учитываются как «Не пришли» — отображается отдельный счётчик «Разреш. отсутствие».

**Существующая БД (PostgreSQL):** если таблица `attendance` уже создана, добавьте значение enum:  
`ALTER TYPE attendancestatus ADD VALUE IF NOT EXISTS 'approved_absence';`

---

## 👤 Роли пользователей

| Роль | Доступ |
|------|--------|
| `employee` | Приход/уход, своя история, профиль |
| `admin` | Всё + управление сотрудниками, сетями, QR |
| `manager` | Отчеты, просмотр посещаемости |

---

## 🐳 Продакшн деплой

1. Измените `SECRET_KEY` в `.env`
2. Настройте SSL в `nginx/nginx.conf`
3. Укажите реальные IP офиса в таблице `office_networks`
4. Сгенерируйте QR-код через admin panel
5. Соберите Flutter APK: `flutter build apk --release`

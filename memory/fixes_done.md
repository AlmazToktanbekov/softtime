---
name: Fixes Done — April 2026
description: Список всех исправлений в SoftTime, выполненных в апреле 2026
type: project
---

## Выполненные исправления

**Why:** Комплексный аудит проекта выявил критические ошибки, блокирующие функционал.
**How to apply:** При работе над новыми задачами учитывать эти исправления.

### Flutter
1. `/employees` → `/users` в api_service.dart (ответ backend — PaginatedUsers с полем `items`)
2. Добавлен `FcmService` (lib/core/services/fcm_service.dart) — инициализация Firebase + сохранение токена
3. Добавлен `updateFcmToken` метод в ApiService
4. pubspec.yaml: добавлены `firebase_core` и `firebase_messaging`
5. main.dart: вызов `FcmService.init()` при запуске

### Backend
6. Создан `app/utils/fcm.py` — утилита FCM (httpx, читает FCM_SERVER_KEY из env)
7. .env: добавлена переменная FCM_SERVER_KEY (пустая, нужно заполнить)
8. auth.py: push admins при регистрации нового сотрудника (PENDING)
9. auth.py: новый endpoint POST /auth/fcm-token для сохранения токена устройства
10. users.py: push сотруднику при approve/reject/activate/block
11. news.py: push всем активным при создании новости
12. absence_requests.py: push admins при новой заявке; push сотруднику при approve/reject
13. duty.py: push при назначении, выполнении, swap-запросе, accept/reject swap
14. cron_service.py: добавлен job 23:05 — проверка невыполненных дежурств + уведомление Admin

### Admin Web
15. index.html: убран хардкод credentials (value="admin" / value="admin123")
16. index.html + app.js: добавлена страница "Журнал действий" (Audit Log)
17. app.js: добавлена функция loadAuditLog() с фильтрами

### Уже было реализовано (не требует изменений)
- Валидация 6 часов рабочего дня: backend (employee_schedules.py) + admin web (app.js:1433)
- manual-checkout endpoint в backend совпадает с вызовом в admin web

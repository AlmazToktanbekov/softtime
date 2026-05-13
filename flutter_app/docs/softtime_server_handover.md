# SoftTime — сервер, API и инструкция для другого разработчика

## 1. Кратко о текущем состоянии

Проект **SoftTime** сейчас запущен на **собственном сервере в локальной сети** на Ubuntu.

Текущий сервер:
- ОС: **Ubuntu 20.04.6 LTS**
- Локальный IP сервера: **192.168.50.131**
- Путь проекта на сервере: **`/srv/softtime`**

Проект состоит из:
- `backend` — FastAPI backend
- `admin_web` — HTML/CSS/JS админка
- `flutter_app` — Flutter клиент
- `docker-compose.yml` — запуск backend/db/redis

---

## 2. Где лежит проект

На сервере проект лежит здесь:

```bash
/srv/softtime
```

Основные папки:

```bash
/srv/softtime/backend
/srv/softtime/admin_web
/srv/softtime/flutter_app
```

---

## 3. Как сейчас запускается проект

### 3.1 Backend
Backend запускается через Docker Compose.

Из папки проекта:

```bash
cd /srv/softtime
sudo docker compose up -d --build
```

Проверка статуса:

```bash
sudo docker compose ps
```

Ожидаемый результат:
- `softtime-backend-1` — `Up`
- `softtime-db-1` — `Up (healthy)`
- `softtime-redis-1` — `Up (healthy)`

Остановка:

```bash
sudo docker compose down
```

Пересборка и запуск:

```bash
sudo docker compose up -d --build
```

---

### 3.2 Admin web
Сейчас `admin_web` запускается **временно** через Python HTTP server:

```bash
cd /srv/softtime/admin_web
python3 -m http.server 8081 --bind 0.0.0.0
```

Открывается по адресу:

```text
http://192.168.50.131:8081
```

Важно:
- если закрыть терминал или нажать `Ctrl + C`, `admin_web` остановится
- это временный способ
- в дальнейшем лучше перевести `admin_web` на **Nginx**

---

## 4. Какие сервисы и порты используются

### Backend
- Внутри контейнера: `8000`
- Снаружи сервера: `8001`

Адрес backend:

```text
http://192.168.50.131:8001
```

Swagger:

```text
http://192.168.50.131:8001/docs
```

OpenAPI JSON:

```text
http://192.168.50.131:8001/openapi.json
```

### Admin web
- Порт: `8081`

Адрес:

```text
http://192.168.50.131:8081
```

### PostgreSQL
- Внутри Docker сети: `db:5432`
- Снаружи сервера наружу **не публикуется**

### Redis
- Внутри Docker сети: `redis:6379`
- Снаружи сейчас доступен через `6379`

---

## 5. Почему backend работает на 8001, а не 8000

На этом сервере уже был другой проект (`TaskFlow`), который использовал:
- порт `8000` для backend
- порт `5432` для PostgreSQL

Чтобы избежать конфликта:
- SoftTime backend вынесен на **`8001`**
- SoftTime PostgreSQL оставлен только внутри Docker-сети

---

## 6. Как устроен docker-compose

Сейчас в `docker-compose.yml` используются сервисы:
- `db` — PostgreSQL 15 Alpine
- `redis` — Redis 7 Alpine
- `backend` — FastAPI backend

Ключевые моменты:
- `backend` собирается через:

```yaml
build: ./backend
```

- backend публикуется так:

```yaml
ports:
  - "8001:8000"
```

- db **не должна** публиковаться как `5432:5432`, иначе будет конфликт с другим проектом

- backend подключается к БД по внутреннему адресу Docker:

```text
db:5432
```

- backend подключается к Redis по внутреннему адресу Docker:

```text
redis:6379
```

---

## 7. API base URL для frontend/admin_web

### Важно
У `admin_web` была ошибка: он по умолчанию ходил на порт `8000`, но SoftTime backend работает на `8001`.

Нужно использовать такой API base URL:

```text
http://192.168.50.131:8001/api/v1
```

Или в общем виде, если открывается по IP/домену текущего сервера:

```js
const host = window.location.hostname || 'localhost';
return `${window.location.protocol}//${host}:8001/api/v1`;
```

---

## 8. Где был исправлен admin_web

Файл:

```bash
/srv/softtime/admin_web/js/app.js
```

В начале файла есть блок:

```js
const API = (() => {
  ...
})();
```

Там нужно использовать порт **8001**, а не `8000`.

Правильный вариант:

```js
if (window.location.protocol.startsWith('http')) {
  const host = window.location.hostname || 'localhost';
  return `${window.location.protocol}//${host}:8001/api/v1`;
}

return 'http://localhost:8001/api/v1';
```

---

## 9. Основные API маршруты

Судя по Swagger, backend использует префикс:

```text
/api/v1
```

### Аутентификация
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/fcm-token`
- `GET /api/v1/auth/register/mentors`

### Пользователи
- `GET /api/v1/users`
- `POST /api/v1/users`
- `GET /api/v1/users/pending`
- и другие user-related endpoints

### Другие используемые разделы по коду admin panel
По `admin_web/js/app.js` используются маршруты вроде:
- `/settings/work-time`
- `/attendance/...`
- `/attendance/approved-absence`
- `/reports/daily`
- `/absence-requests/...`
- `/auth/me`
- `/users`

Полный список нужно смотреть через Swagger:

```text
http://192.168.50.131:8001/docs
```

---

## 10. Авторизация

В `admin_web` используется JWT-логика:

### Login
Запрос:

```http
POST /api/v1/auth/login
Content-Type: application/json
```

Body:

```json
{
  "username": "admin",
  "password": "..."
}
```

После успешного входа сохраняются:
- `access_token`
- `refresh_token`

в `localStorage` браузера.

### Refresh
При 401 вызывается:

```http
POST /api/v1/auth/refresh
```

После этого токен обновляется.

### Заголовок для защищенных запросов

```http
Authorization: Bearer <access_token>
```

---

## 11. Как проверить, что backend работает

На сервере:

```bash
cd /srv/softtime
sudo docker compose ps
```

Проверка порта:

```bash
sudo ss -tulpn | grep 8001
```

Проверка Swagger:

```bash
curl http://127.0.0.1:8000/docs
```

С другого устройства в этой же локальной сети:

```text
http://192.168.50.131:8001/docs
```

---

## 12. Как проверить, что admin_web работает

Запуск:

```bash
cd /srv/softtime/admin_web
python3 -m http.server 8081 --bind 0.0.0.0
```

Проверка на сервере:

```bash
curl http://127.0.0.1:8081
```

Проверка с другого устройства:

```text
http://192.168.50.131:8081
```

Если не открывается:
- проверить, не остановлен ли Python server
- проверить firewall
- проверить, что порт 8081 разрешен

Открытие порта:

```bash
sudo ufw allow 8081/tcp
sudo ufw reload
```

---

## 13. Важные проблемы, которые уже встречались

### 1. Конфликт портов
На сервере уже был другой проект, который использовал:
- `8000`
- `5432`

Из-за этого SoftTime не запускался, пока порты не были изменены.

### 2. Ошибка docker compose
Была ошибка:

```text
service "backend" has neither an image nor a build context specified
```

Причина:
- в `docker-compose.yml` у `backend` пропала строка:

```yaml
build: ./backend
```

### 3. Admin web открывался, но login давал `Not Found`
Причина:
- `admin_web/js/app.js` использовал API на `8000`
- backend реально работал на `8001`

### 4. HTML не открывался
Причина:
- Python server был остановлен через `Ctrl + C`

---

## 14. Что важно знать другому разработчику

### Сейчас сервер не внешний
Сервер находится в **локальной сети**, потому что используется локальный IP:

```text
192.168.50.131
```

Это значит:
- внутри этой сети всё может работать
- извне интернета проект **не будет доступен**

### Чтобы проект работал "везде", нужно:
- VPS или внешний белый IP
- домен
- Nginx
- HTTPS
- проброс портов / настройка сети

---

## 15. Рекомендации по улучшению

### 1. Перевести `admin_web` на Nginx
Сейчас он запускается временно через Python server. Лучше раздавать его через Nginx.

### 2. Сделать systemd / постоянный запуск
Чтобы после перезагрузки сервера все автоматически поднималось.

### 3. Использовать домен
Например:

```text
https://softtime.example.com
https://api.softtime.example.com
```

### 4. Настроить HTTPS
Через Nginx + Certbot.

### 5. Не хранить чувствительные данные в коде
Все секреты держать в `.env`.

### 6. Описать роли и пользователей
Нужно отдельно документировать:
- какие роли есть
- какие права у каждой роли
- какой логин у стартового администратора

---

## 16. Полезные команды

### Docker
```bash
cd /srv/softtime
sudo docker compose up -d --build
sudo docker compose down
sudo docker compose ps
sudo docker compose logs -f
```

### Проверка портов
```bash
sudo ss -tulpn | grep -E ':8001|:8081|:6379|:5432'
```

### Admin web
```bash
cd /srv/softtime/admin_web
python3 -m http.server 8081 --bind 0.0.0.0
```

### Firewall
```bash
sudo ufw status
sudo ufw allow 8081/tcp
sudo ufw allow 8001/tcp
sudo ufw reload
```

---

## 17. Текущие адреса для разработки

### Backend API
```text
http://192.168.50.131:8001/api/v1
```

### Swagger
```text
http://192.168.50.131:8001/docs
```

### Admin Panel
```text
http://192.168.50.131:8081
```

---

## 18. Итог

На текущий момент:
- SoftTime backend поднят и работает через Docker
- PostgreSQL и Redis подняты
- admin_web работает отдельно как статический frontend
- admin_web использует backend на порту `8001`
- сервер пока рассчитан на работу **в локальной сети**, а не в публичном интернете

Если другой разработчик продолжит работу, ему в первую очередь нужно:
1. проверить `docker-compose.yml`
2. проверить `.env`
3. проверить `admin_web/js/app.js`
4. проверить доступность `8001` и `8081`
5. решить, будет ли проект оставаться локальным или переноситься на внешний сервер

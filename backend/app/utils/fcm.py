"""
Firebase Cloud Messaging (FCM) push notification helper.

Требует в .env:
    FCM_SERVER_KEY=<ваш ключ из Firebase Console → Project Settings → Cloud Messaging>

Если ключ не задан — уведомления логируются как предупреждение, но не падают.
"""
import logging
import os
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

FCM_SERVER_KEY: Optional[str] = os.environ.get("FCM_SERVER_KEY")
FCM_URL = "https://fcm.googleapis.com/fcm/send"


def _send_raw(token: str, title: str, body: str, data: Optional[dict] = None) -> bool:
    """Отправить одно уведомление на токен устройства. Возвращает True при успехе."""
    if not FCM_SERVER_KEY:
        logger.warning(
            "[FCM] FCM_SERVER_KEY не задан — уведомление не отправлено. "
            "Добавьте FCM_SERVER_KEY в .env"
        )
        return False

    payload: dict = {
        "to": token,
        "notification": {"title": title, "body": body, "sound": "default"},
        "priority": "high",
    }
    if data:
        payload["data"] = data

    try:
        resp = httpx.post(
            FCM_URL,
            json=payload,
            headers={
                "Authorization": f"key={FCM_SERVER_KEY}",
                "Content-Type": "application/json",
            },
            timeout=10.0,
        )
        if resp.status_code == 200:
            result = resp.json()
            if result.get("failure", 0) > 0:
                logger.warning(f"[FCM] Ошибка доставки на токен {token[:20]}...: {result}")
                return False
            return True
        else:
            logger.error(f"[FCM] HTTP {resp.status_code}: {resp.text}")
            return False
    except Exception as exc:
        logger.error(f"[FCM] Исключение при отправке: {exc}")
        return False


def notify_user(user, title: str, body: str, data: Optional[dict] = None) -> bool:
    """Отправить уведомление пользователю по его fcm_token."""
    if not user or not getattr(user, "fcm_token", None):
        return False
    return _send_raw(user.fcm_token, title, body, data)


def notify_users(users, title: str, body: str, data: Optional[dict] = None) -> int:
    """Отправить уведомление списку пользователей. Возвращает количество успешных."""
    count = 0
    for user in users:
        if notify_user(user, title, body, data):
            count += 1
    return count

"""
Firebase Cloud Messaging (FCM) push notification helper using firebase-admin.
"""
import logging
import os
from typing import Optional

import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger(__name__)

# Initialize Firebase Admin SDK
try:
    if not firebase_admin._apps:
        # Assuming the JSON file is in the 'backend' folder
        cred_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "firebase-adminsdk.json")
        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            logger.info("Firebase Admin SDK initialized successfully.")
        else:
            logger.warning(f"Firebase Admin SDK credentials not found at {cred_path}.")
except Exception as e:
    logger.error(f"Error initializing Firebase Admin SDK: {e}")


def _send_raw(token: str, title: str, body: str, data: Optional[dict] = None) -> bool:
    """Отправить одно уведомление на токен устройства. Возвращает True при успехе."""
    if not firebase_admin._apps:
        logger.warning("[FCM] Firebase App not initialized.")
        return False

    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        token=token,
    )
    
    # Only string values are allowed in 'data' dictionary for FCM
    if data:
        message.data = {str(k): str(v) for k, v in data.items()}

    try:
        response = messaging.send(message)
        logger.info(f"Successfully sent message: {response}")
        return True
    except Exception as e:
        logger.error(f"[FCM] Исключение при отправке на токен {token[:20]}...: {e}")
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

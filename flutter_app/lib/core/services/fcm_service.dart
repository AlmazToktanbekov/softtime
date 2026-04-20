import 'dart:developer';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

/// Firebase Cloud Messaging сервис.
///
/// Требования перед использованием:
/// - Android: добавить `android/app/google-services.json` из Firebase Console
/// - iOS: добавить `ios/Runner/GoogleService-Info.plist` из Firebase Console
/// - Запустить `flutterfire configure` (пакет flutterfire_cli)
///
/// Без этих файлов Firebase.initializeApp() бросит исключение — оно перехватывается.
class FcmService {
  static Future<void> init() async {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 4));
    } catch (e) {
      log('[FCM] Firebase не инициализирован: $e\n'
          'Добавьте google-services.json / GoogleService-Info.plist из Firebase Console.');
      return;
    }

    final messaging = FirebaseMessaging.instance;

    // Запрос разрешения (iOS / macOS)
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      log('[FCM] requestPermission timeout/error: $e');
    }

    // Получаем токен и сохраняем на сервере
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await ApiService().updateFcmToken(token);
        log('[FCM] Токен зарегистрирован на сервере');
      }
    } catch (e) {
      log('[FCM] Не удалось получить токен: $e');
    }

    // При обновлении токена — повторно отправляем на сервер
    messaging.onTokenRefresh.listen((newToken) async {
      await ApiService().updateFcmToken(newToken);
    });

    // Обработка уведомлений в foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('[FCM] Уведомление: ${message.notification?.title} — ${message.notification?.body}');
      // TODO: показывать локальное уведомление через flutter_local_notifications
    });
  }
}

import 'dart:async';
import 'dart:developer';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

class FcmService {
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _messageSub;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 4));
    } catch (e) {
      log('[FCM] Firebase не инициализирован: $e');
      return;
    }

    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      log('[FCM] requestPermission error: $e');
    }

    try {
      final token = await messaging.getToken();
      if (token != null) {
        await ApiService().updateFcmToken(token);
        log('[FCM] Токен зарегистрирован');
      }
    } catch (e) {
      log('[FCM] Не удалось получить токен: $e');
    }

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      try { await ApiService().updateFcmToken(newToken); } catch (_) {}
    });

    _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('[FCM] ${message.notification?.title} — ${message.notification?.body}');
    });
  }

  static void dispose() {
    _tokenRefreshSub?.cancel();
    _messageSub?.cancel();
    _tokenRefreshSub = null;
    _messageSub = null;
  }
}

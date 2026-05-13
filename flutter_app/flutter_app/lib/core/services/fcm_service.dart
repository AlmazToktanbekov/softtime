import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../../firebase_options.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

class FcmService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    try {
      // Try to initialize Firebase with error handling
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        debugPrint('[FCM] Firebase init failed: $e - continuing without FCM');
        return;
      }

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      
      // Request permission with timeout
      try {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[FCM] Permission request failed: $e');
      }

      // Setup local notifications
      try {
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        const iosInit = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
        await _localNotifications.initialize(settings: initSettings);
      } catch (e) {
        debugPrint('[FCM] Local notifications init failed: $e');
      }

      // Listen to foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        try {
          if (message.notification != null) {
            _showLocalNotification(message);
          }
        } catch (e) {
          debugPrint('[FCM] Failed to handle foreground message: $e');
        }
      });

      // Get and send FCM token
      try {
        final token = await messaging.getToken().timeout(const Duration(seconds: 5));
        if (token != null && token.isNotEmpty) {
          try {
            await ApiService().updateFcmToken(token).timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('[FCM] Token update failed (non-fatal): $e');
          }
        }
      } catch (e) {
        debugPrint('[FCM] Failed to get token: $e');
      }

      // Listen for token refresh
      try {
        messaging.onTokenRefresh.listen((newToken) {
          try {
            ApiService().updateFcmToken(newToken);
          } catch (_) {}
        });
      } catch (e) {
        debugPrint('[FCM] Token refresh listener error: $e');
      }

    } catch (e) {
      debugPrint('[FCM] Critical init error: $e - app continues without notifications');
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel', // channel Id
      'High Importance Notifications', // channel Name
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title,
      body: message.notification?.body,
      notificationDetails: details,
    );
  }

  static Future<void> updateToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        debugPrint('FCM Token (update): $token');
        await ApiService().updateFcmToken(token);
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  static void dispose() {}
}

class AppConfig {
  // ── Продакшн URL ─────────────────────────────────────────────────────────────
  // Задаётся при сборке через --dart-define=API_BASE_URL=https://your-server.com/api/v1
  // Или замените defaultValue на URL вашего сервера перед сборкой APK/IPA.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.50.12:8000',
  );

  static const int connectTimeout = 15000;
  static const int receiveTimeout = 15000;
}

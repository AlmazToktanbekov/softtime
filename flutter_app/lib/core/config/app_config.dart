class AppConfig {
  // ── Продакшн URL (задеплоенный сервер) ──────────────────────────────────────
  // Когда задеплоите на Railway/VPS — вставьте сюда постоянный URL:
  // static const String _productionUrl = 'https://your-app.railway.app';

  // ── Дефолтный URL (можно переопределить через диалог в приложении) ──────────
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.50.12:8000',
  );

  static const int connectTimeout = 15000;
  static const int receiveTimeout = 15000;
}

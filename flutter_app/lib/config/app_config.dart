class AppConfig {
  // Можно переопределить при запуске:
  // flutter run --dart-define=API_BASE_URL=http://<IP_СЕРВЕРА>:8000/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.50.177:8000/api/v1',
  );
  // Change to your production URL:
  // static const String baseUrl = 'https://your-domain.com/api/v1';

  static const int connectTimeout = 10000;
  static const int receiveTimeout = 10000;
}

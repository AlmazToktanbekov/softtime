import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'router.dart';
import 'core/services/api_service.dart';
import 'core/theme/app_theme.dart';
import 'core/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Системные настройки
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initializeDateFormatting('ru', null);
  debugPrint('[Main] Date formatting initialized');

  // Initialize API before anything else
  try {
    await ApiService().init();
    debugPrint('[Main] ApiService initialized');
  } catch (e) {
    debugPrint('[Main] Error initializing ApiService: $e');
  }

  // Firebase + FCM initialization with timeout to prevent app hang
  // This runs in the background and doesn't block app startup
  Future.delayed(const Duration(milliseconds: 500), () {
    FcmService.init().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[FCM] Init timeout - continuing without FCM');
      },
    ).catchError((e) {
      debugPrint('[FCM] Init error: $e');
    });
  });

  debugPrint('[Main] Running app');
  runApp(const ProviderScope(child: SoftTimeApp()));
}

class SoftTimeApp extends ConsumerWidget {
  const SoftTimeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'SoftTime',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      locale: const Locale('ru'),
    );
  }
}

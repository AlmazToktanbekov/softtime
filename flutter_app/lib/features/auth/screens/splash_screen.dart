import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    debugPrint('[Splash] initState');
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    debugPrint('[Splash] _navigate start');
    try {
      final results = await Future.wait<dynamic>([
        Future.delayed(const Duration(milliseconds: 1500)),
        ref.read(authProvider.notifier).init().timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        ).catchError((e) {
          debugPrint('[Splash] Auth init error: \$e');
          return false;
        }),
      ]);
      debugPrint('[Splash] init results: $results');
    } catch (e) {
      debugPrint('[Splash] Navigation setup error: \$e');
    }

    if (!mounted) return;

    try {
      final auth = ref.read(authProvider);
      debugPrint('[Splash] auth status: isAuthenticated=${auth.isAuthenticated}, role=${auth.user?.role}');
      if (auth.isAuthenticated) {
        debugPrint('[Splash] Navigating to /home');
        context.go('/home');
      } else {
        debugPrint('[Splash] Navigating to /login');
        context.go('/login');
      }
    } catch (e) {
      debugPrint('[Splash] Navigation failed: \$e');
      if (mounted) {
        debugPrint('[Splash] Falling back to /login');
        context.go('/login');
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4361EE).withValues(alpha: 0.6),
                          blurRadius: 40,
                          spreadRadius: 4,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SoftTime',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Система управления офисом',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0x99FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


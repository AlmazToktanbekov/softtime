import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/registration_screen.dart';
import 'features/home/screens/main_shell.dart';
import 'features/home/screens/home_screen.dart';
import 'features/duty/screens/duty_screen.dart';
import 'features/news/screens/news_screen.dart';
import 'features/news/screens/news_detail_screen.dart';
import 'features/attendance/screens/qr_scanner_screen.dart';
import 'features/attendance/screens/history_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/requests/screens/requests_screen.dart';
import 'features/schedule/screens/schedule_screen.dart';
import 'features/tasks/screens/tasks_screen.dart';
import 'features/team/screens/team_screen.dart';

// Admin
import 'features/admin/admin_shell.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/admin/screens/admin_employees_screen.dart';
import 'features/admin/screens/admin_attendance_screen.dart';
import 'features/admin/screens/admin_reports_screen.dart';
import 'features/admin/screens/admin_more_screen.dart';
import 'features/admin/screens/admin_leave_requests_screen.dart';
import 'features/admin/screens/admin_networks_screen.dart';
import 'features/admin/screens/admin_qr_screen.dart';
import 'features/news/screens/admin_news_screen.dart';
import 'features/duty/screens/admin_duty_screen.dart';
import 'features/schedule/screens/admin_schedule_screen.dart';

import 'core/services/auth_provider.dart';

final _rootNavigatorKey  = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final _adminShellNavigatorKey = GlobalKey<NavigatorState>();

// ChangeNotifier, который сообщает GoRouter о смене состояния авторизации.
// Создаётся один раз — GoRouter НЕ пересоздаётся.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

final _routerNotifierProvider = ChangeNotifierProvider<_RouterNotifier>(
  (ref) => _RouterNotifier(ref),
);

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final loggedIn = auth.isAuthenticated;
      final isAdmin = auth.isAdmin;

      const publicRoutes = {'/splash', '/login', '/register'};
      if (!loggedIn && !publicRoutes.contains(loc)) return '/login';

      if (loggedIn && (loc == '/login' || loc == '/register')) {
        return isAdmin ? '/admin' : '/home';
      }

      if (loggedIn && isAdmin && loc == '/home') return '/admin';
      if (loggedIn && !isAdmin && loc.startsWith('/admin')) return '/home';

      return null;
    },
    routes: [
      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => _fadeRoute(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) => _slideRoute(state, const RegistrationScreen()),
      ),

      // ── QR Scanner ────────────────────────────────────────────────────────
      GoRoute(
        path: '/qr-scanner',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final mode = state.extra as String? ?? 'check_in';
          return _fadeRoute(state, QRScannerScreen(mode: mode));
        },
      ),

      // ── Admin shell ───────────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _adminShellNavigatorKey,
        pageBuilder: (context, state, child) {
          return NoTransitionPage(child: AdminShell(child: child));
        },
        routes: [
          GoRoute(
            path: '/admin',
            pageBuilder: (_, state) =>
                _fadeRoute(state, const AdminDashboardScreen()),
          ),
          GoRoute(
            path: '/admin/employees',
            pageBuilder: (_, state) =>
                _slideRoute(state, const AdminEmployeesScreen()),
          ),
          GoRoute(
            path: '/admin/attendance',
            pageBuilder: (_, state) =>
                _slideRoute(state, const AdminAttendanceScreen()),
          ),
          GoRoute(
            path: '/admin/reports',
            pageBuilder: (_, state) =>
                _slideRoute(state, const AdminReportsScreen()),
          ),
          GoRoute(
            path: '/admin/more',
            pageBuilder: (_, state) =>
                _slideRoute(state, const AdminMoreScreen()),
          ),
        ],
      ),

      // ── Admin full-screen push routes ─────────────────────────────────────
      GoRoute(
        path: '/admin/news',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) => _slideRoute(state, const AdminNewsScreen()),
      ),
      GoRoute(
        path: '/admin/duty',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) => _slideRoute(state, const AdminDutyScreen()),
      ),
      GoRoute(
        path: '/admin/schedule',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) =>
            _slideRoute(state, const AdminScheduleScreen()),
      ),
      GoRoute(
        path: '/admin/requests',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) =>
            _slideRoute(state, const AdminLeaveRequestsScreen()),
      ),
      GoRoute(
        path: '/admin/qr',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) => _slideRoute(state, const AdminQrScreen()),
      ),
      GoRoute(
        path: '/admin/networks',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) =>
            _slideRoute(state, const AdminNetworksScreen()),
      ),

      // ── Employee shell ────────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        pageBuilder: (context, state, child) {
          return NoTransitionPage(child: MainShell(child: child));
        },
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, state) => _slideRoute(state, const HomeScreen()),
            routes: [
              GoRoute(
                path: 'history',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) =>
                    _slideRoute(state, const HistoryScreen()),
              ),
              GoRoute(
                path: 'schedule',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) =>
                    _slideRoute(state, const ScheduleScreen()),
              ),
              GoRoute(
                path: 'requests',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) =>
                    _slideRoute(state, const RequestsScreen()),
              ),
              GoRoute(
                path: 'profile',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) =>
                    _slideRoute(state, const ProfileScreen()),
              ),
              GoRoute(
                path: 'tasks',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) =>
                    _slideRoute(state, const TasksScreen()),
              ),
              GoRoute(
                path: 'team',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) =>
                    _slideRoute(state, const TeamScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/duty',
            pageBuilder: (_, state) => _slideRoute(state, const DutyScreen()),
          ),
          GoRoute(
            path: '/news',
            pageBuilder: (_, state) => _slideRoute(state, const NewsScreen()),
            routes: [
              GoRoute(
                path: ':newsId',
                parentNavigatorKey: _rootNavigatorKey,
                pageBuilder: (_, state) {
                  final newsId = state.pathParameters['newsId']!;
                  return _slideRoute(state, NewsDetailScreen(newsId: newsId));
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

// ─── Page transitions ──────────────────────────────────────────────────────────

CustomTransitionPage<void> _slideRoute(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      final tween =
          Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOutCubic));
      return SlideTransition(
        position: animation.drive(tween),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}

CustomTransitionPage<void> _fadeRoute(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

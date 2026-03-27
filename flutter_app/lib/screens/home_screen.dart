import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../services/auth_provider.dart';
import '../models/attendance_model.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  AttendanceModel? _todayRecord;
  bool _initialLoading = true;
  bool _refreshing = false;
  bool _hasLoadedOnce = false;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTodayRecord();
  }

  Future<void> _loadTodayRecord() async {
    if (mounted) {
      setState(() {
        // Не показываем “пустой” загрузчик в карточке при повторных обновлениях,
        // чтобы UI не мерцал. Индикатор покажем аккуратно в шапке карточки.
        if (_todayRecord == null && !_hasLoadedOnce) {
          _initialLoading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final records = await ref.read(apiServiceProvider).getMyAttendance(
            startDate: today,
            endDate: today,
          );

      if (!mounted) return;

      setState(() {
        _todayRecord = records.isNotEmpty ? records.first : null;
        _initialLoading = false;
        _refreshing = false;
        _hasLoadedOnce = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _refreshing = false;
        _hasLoadedOnce = true;
      });
    }
  }

  Future<void> _onCheckIn() async {
    final result = await context.push('/qr-scanner', extra: 'check_in');

    if (result is String) {
      if (mounted) {
        setState(() => _actionLoading = true);
      }

      try {
        final record = await ref.read(apiServiceProvider).checkIn(result);

        if (!mounted) return;

        setState(() {
          _todayRecord = record;
          _actionLoading = false;
        });

        _showSuccess('Приход успешно отмечен! 🎉');
      } catch (e) {
        if (!mounted) return;

        setState(() => _actionLoading = false);
        _showError(_parseError(e));
      }
    }
  }

  Future<void> _onCheckOut() async {
    final result = await context.push('/qr-scanner', extra: 'check_out');

    if (result is String) {
      if (mounted) {
        setState(() => _actionLoading = true);
      }

      try {
        final record = await ref.read(apiServiceProvider).checkOut(result);

        if (!mounted) return;

        setState(() {
          _todayRecord = record;
          _actionLoading = false;
        });

        _showSuccess('Уход успешно отмечен! 👋');
      } catch (e) {
        if (!mounted) return;

        setState(() => _actionLoading = false);
        _showError(_parseError(e));
      }
    }
  }

  String _parseError(dynamic e) {
    // 1) Если это DioException — пробуем вытащить detail прямо из ответа
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    }

    // 2) Fallback: парсим detail из строки (на случай, если тип неизвестен)
    final str = e.toString();

    // Вариант с двойными кавычками: {"detail":"..."}
    final detailMatchDouble =
        RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    if (detailMatchDouble != null) {
      return detailMatchDouble.group(1) ?? 'Произошла ошибка';
    }

    // Вариант с одинарными кавычками: {'detail': '...'}
    final detailMatchSingle =
        RegExp(r"'detail'\s*:\s*'([^']+)'").firstMatch(str);
    if (detailMatchSingle != null) {
      return detailMatchSingle.group(1) ?? 'Произошла ошибка';
    }

    final urlMatch = RegExp(r'https?://[^\s"]+').firstMatch(str);
    final url = urlMatch?.group(0);

    if (str.contains('SocketException') ||
        str.contains('Failed host lookup') ||
        str.contains('Connection refused') ||
        str.contains('timed out')) {
      return url != null
          ? 'Нет подключения к серверу: $url'
          : 'Ошибка подключения к серверу';
    }

    return 'Произошла ошибка';
  }

  void _showSuccess(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final employee = auth.employee;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Доброе утро'
        : now.hour < 17
            ? 'Добрый день'
            : 'Добрый вечер';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF888899),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              employee?.fullName ?? 'Сотрудник',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.person_outline_rounded,
              color: Color(0xFF888899),
            ),
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: Color(0xFF888899),
            ),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTodayRecord,
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateCard(now: now),
              const SizedBox(height: 20),
              _TodayCard(
                record: _todayRecord,
                initialLoading: _initialLoading,
                refreshing: _refreshing,
              ),
              const SizedBox(height: 20),
              if (_actionLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                )
              else
                _ActionButtons(
                  record: _todayRecord,
                  onCheckIn: _onCheckIn,
                  onCheckOut: _onCheckOut,
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _QuickLink(
                      icon: Icons.history_rounded,
                      label: 'История',
                      color: AppTheme.primary,
                      onTap: () => context.push('/history'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _QuickLink(
                      icon: Icons.description_outlined,
                      label: 'Заявки',
                      color: AppTheme.statusApprovedAbsence,
                      onTap: () => context.push('/requests'),
                    ),
                  ),
                  if (auth.isAdmin) const SizedBox(width: 14),
                  if (auth.isAdmin)
                    Expanded(
                      child: _QuickLink(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Админ',
                        color: AppTheme.warning,
                        onTap: () => context.push('/admin'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateCard extends StatelessWidget {
  final DateTime now;
  const _DateCard({required this.now});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE', 'ru').format(now).capitalize(),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('d MMMM yyyy', 'ru').format(now),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final AttendanceModel? record;
  final bool initialLoading;
  final bool refreshing;

  const _TodayCard({
    required this.record,
    required this.initialLoading,
    required this.refreshing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEEEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Статус сегодня',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888899),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (refreshing) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              ],
              const Spacer(),
              StatusBadge(status: record?.status ?? 'absent'),
            ],
          ),
          const SizedBox(height: 20),
          if (initialLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(
                  color: AppTheme.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _TimeBox(
                    label: 'Приход',
                    time: record?.formattedCheckIn ?? '--:--',
                    icon: Icons.login_rounded,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _TimeBox(
                    label: 'Уход',
                    time: record?.formattedCheckOut ?? '--:--',
                    icon: Icons.logout_rounded,
                    color: AppTheme.error,
                  ),
                ),
                if (record?.workDuration != null) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: _TimeBox(
                      label: 'Время',
                      time: record!.workDuration!,
                      icon: Icons.timer_outlined,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            if (record != null && record!.lateMinutes > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.warning,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Опоздание: ${record!.lateMinutes} мин',
                      style: const TextStyle(
                        color: AppTheme.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final Color color;

  const _TimeBox({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            time,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF888899)),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final AttendanceModel? record;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _ActionButtons({
    required this.record,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  bool get _canCheckIn => record == null || record!.checkInTime == null;
  bool get _canCheckOut =>
      record?.checkInTime != null && record?.checkOutTime == null;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: _canCheckIn ? onCheckIn : null,
            icon: const Icon(Icons.login_rounded, size: 22),
            label: const Text(
              'Отметить приход',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE8F5E9),
              disabledForegroundColor: const Color(0xFFA5D6A7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: _canCheckOut ? onCheckOut : null,
            icon: const Icon(Icons.logout_rounded, size: 22),
            label: const Text(
              'Отметить уход',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFEBEE),
              disabledForegroundColor: const Color(0xFFEF9A9A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickLink({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
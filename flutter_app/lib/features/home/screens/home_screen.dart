// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/attendance_model.dart';
import '../../../core/models/duty_model.dart';
import '../../../core/models/news_model.dart';
import '../../../core/models/employee_schedule_model.dart';
import '../../../providers.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_badge.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  AttendanceModel? _today;
  List<DutyAssignment> _todayDuties = [];
  List<News> _news = [];
  List<EmployeeScheduleModel> _schedules = [];

  bool _loadingAttendance = true;
  bool _loadingDuty = true;
  bool _loadingNews = true;
  bool _loadingSchedule = true;
  bool _actionLoading = false;
  String? _error;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Живой таймер для рабочего времени
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadAttendance();
    _loadDuty();
    _loadNews();
    _loadSchedule();
  }

  Future<void> _loadAttendance() async {
    setState(() => _loadingAttendance = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final api = ref.read(apiServiceProvider);
      final records = await api.getMyAttendance(startDate: today, endDate: today);
      if (mounted) setState(() => _today = records.isNotEmpty ? records.first : null);
    } catch (e) {
      if (mounted) setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _loadingAttendance = false);
    }
  }

  Future<void> _loadDuty() async {
    setState(() => _loadingDuty = true);
    try {
      final api = ref.read(apiServiceProvider);
      final duties = await api.getTodayDuties();
      if (mounted) setState(() => _todayDuties = duties);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingDuty = false);
    }
  }

  Future<void> _loadNews() async {
    setState(() => _loadingNews = true);
    try {
      final api = ref.read(apiServiceProvider);
      final news = await api.getNews();
      if (mounted) setState(() => _news = news.take(2).toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingNews = false);
    }
  }

  Future<void> _loadSchedule() async {
    setState(() => _loadingSchedule = true);
    try {
      final auth = ref.read(authProvider);
      final userId = auth.user?.id;
      if (userId == null) return;
      final api = ref.read(apiServiceProvider);
      final s = await api.getEmployeeSchedules(userId);
      if (mounted) setState(() => _schedules = s);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSchedule = false);
    }
  }

  Future<void> _onCheckIn() async {
    final result = await context.push<String>('/qr-scanner', extra: 'check_in');
    if (result == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      final record = await ref.read(apiServiceProvider).checkIn(result);
      if (!mounted) return;
      setState(() { _today = record; _actionLoading = false; });
      _showSnack('Приход отмечен!', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      _showSnack(_parseError(e), AppColors.error);
    }
  }

  Future<void> _onCheckOut() async {
    final result = await context.push<String>('/qr-scanner', extra: 'check_out');
    if (result == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      final record = await ref.read(apiServiceProvider).checkOut(result);
      if (!mounted) return;
      setState(() { _today = record; _actionLoading = false; });
      _showSnack('Уход отмечен!', AppColors.primary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      _showSnack(_parseError(e), AppColors.error);
    }
  }

  String _parseError(dynamic e) {
    final s = e.toString();
    final m = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(s);
    if (m != null) return m.group(1)!;
    if (s.contains('SocketException') || s.contains('refused') || s.contains('timed out')) {
      return 'Нет подключения к серверу';
    }
    return 'Произошла ошибка';
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      backgroundColor: color,
    ));
  }

  // Сегодняшнее расписание (0=Пн … 6=Вс)
  EmployeeScheduleModel? get _todaySchedule {
    final dow = DateTime.now().weekday - 1;
    try {
      return _schedules.firstWhere((s) => s.dayOfWeek == dow);
    } catch (_) {
      return null;
    }
  }

  bool _isMyLunchDutyToday(String? userId) {
    if (userId == null) return false;
    return _todayDuties.any((d) => d.userId == userId && d.isLunch);
  }

  String _liveWorkTime() {
    if (_today?.checkInTime == null) return '';
    final inDt = DateTime.parse(_today!.checkInTime!).toLocal();
    final now = DateTime.now();
    final diff = now.difference(inDt);
    if (diff.isNegative) return '';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? '$h ч $m м' : '$m м';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Доброе утро' : now.hour < 18 ? 'Добрый день' : 'Добрый вечер';
    final firstName = user?.fullName?.split(' ').first ?? 'Сотрудник';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          setState(() => _error = null);
          await _loadAll();
        },
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 20,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Inter')),
                  Text(firstName,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter')),
                ],
              ),
              actions: [
                if (auth.isAdmin)
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    onPressed: () => context.push('/home/admin'),
                    tooltip: 'Панель Admin',
                  ),
                GestureDetector(
                  onTap: () => context.push('/home/profile'),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            fontFamily: 'Inter'),
                      ),
                    ),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: AppColors.divider),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Ошибка сети ────────────────────────────────────────
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.error,
                                  fontFamily: 'Inter'),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _loadAll();
                            },
                            child: const Text('Повтор',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Дата ──────────────────────────────────────────────
                  _DateBanner(now: now),
                  const SizedBox(height: 16),

                  // ── Посещаемость ───────────────────────────────────────
                  _AttendanceCard(
                    record: _today,
                    loading: _loadingAttendance,
                    actionLoading: _actionLoading,
                    schedule: _todaySchedule,
                    liveTime: _liveWorkTime(),
                    onCheckIn: _onCheckIn,
                    onCheckOut: _onCheckOut,
                    enableCheckInOut: !auth.isAdmin,
                  ),
                  const SizedBox(height: 16),

                  if (_isMyLunchDutyToday(user?.id)) ...[
                    _LunchDutyCallout(onOpen: () => context.go('/duty')),
                    const SizedBox(height: 16),
                  ],

                  // ── Дежурство ──────────────────────────────────────────
                  _DutySectionHome(
                    duties: _todayDuties,
                    loading: _loadingDuty,
                    currentUserId: user?.id,
                    onOpen: () => context.go('/duty'),
                  ),
                  const SizedBox(height: 16),

                  // ── Мой график (мини) ──────────────────────────────────
                  _ScheduleMini(
                    schedules: _schedules,
                    loading: _loadingSchedule,
                    onTap: () => context.push('/home/schedule'),
                  ),
                  const SizedBox(height: 16),

                  // ── Последние новости ──────────────────────────────────
                  _NewsMini(
                    news: _news,
                    loading: _loadingNews,
                    onAll: () => context.go('/news'),
                    onItem: (id) => context.push('/news/$id'),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Subwidgets
// ══════════════════════════════════════════════════════════════════════════════

class _DateBanner extends StatelessWidget {
  final DateTime now;
  const _DateBanner({required this.now});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE', 'ru').format(now).capitalize(),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, fontFamily: 'Inter'),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('d MMMM yyyy', 'ru').format(now),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter'),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.calendar_today_rounded,
                color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

// ─── Attendance Card ───────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final AttendanceModel? record;
  final bool loading;
  final bool actionLoading;
  final EmployeeScheduleModel? schedule;
  final String liveTime;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  /// Для админа: без QR-отметки прихода/ухода в этом блоке (учёт — в панели).
  final bool enableCheckInOut;

  const _AttendanceCard({
    required this.record,
    required this.loading,
    required this.actionLoading,
    required this.schedule,
    required this.liveTime,
    required this.onCheckIn,
    required this.onCheckOut,
    this.enableCheckInOut = true,
  });

  bool get _canCheckIn => record == null || record!.checkInTime == null;
  bool get _canCheckOut => record?.checkInTime != null && record?.checkOutTime == null;
  bool get _done => record?.checkOutTime != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: loading
          ? const _Shimmer(height: 100)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Посещаемость сегодня',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontFamily: 'Inter')),
                    const Spacer(),
                    if (record != null) StatusBadge(status: record!.status),
                  ],
                ),
                const SizedBox(height: 16),

                // Расписание сегодня
                if (schedule != null && schedule!.isWorkingDay) ...[
                  Row(children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'График: ${schedule!.formattedStart} – ${schedule!.formattedEnd}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter'),
                    ),
                  ]),
                  const SizedBox(height: 14),
                ],

                // Временные блоки
                if (!loading)
                  Row(children: [
                    _TimeBox(
                      label: 'Приход',
                      value: record?.formattedCheckIn ?? '--:--',
                      icon: Icons.login_rounded,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    _TimeBox(
                      label: 'Уход',
                      value: record?.formattedCheckOut ?? '--:--',
                      icon: Icons.logout_rounded,
                      color: AppColors.error,
                    ),
                    if (liveTime.isNotEmpty || record?.workDuration != null) ...[
                      const SizedBox(width: 10),
                      _TimeBox(
                        label: _done ? 'Итого' : 'Сейчас',
                        value: _done
                            ? (record?.workDuration ?? '')
                            : liveTime,
                        icon: Icons.timer_outlined,
                        color: AppColors.primary,
                      ),
                    ],
                  ]),

                // Опоздание
                if (record != null && record!.lateMinutes > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Опоздание: ${record!.lateMinutes} мин',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter'),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 16),

                // Кнопки
                if (!enableCheckInOut)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: const Text(
                      'Для учётной записи администратора сканирование QR в этом блоке отключено. '
                      'Посещаемость команды отражается в панели администратора.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontFamily: 'Inter',
                        height: 1.4,
                      ),
                    ),
                  )
                else if (actionLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2.5),
                    ),
                  )
                else
                  _ActionButtons(
                    canCheckIn: _canCheckIn,
                    canCheckOut: _canCheckOut,
                    onCheckIn: onCheckIn,
                    onCheckOut: onCheckOut,
                  ),
              ],
            ),
    );
  }
}

class _LunchDutyCallout extends StatelessWidget {
  final VoidCallback onOpen;
  const _LunchDutyCallout({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.warning.withOpacity(0.45)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.restaurant_menu_rounded,
                      color: AppColors.warning, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Вы дежурный по обеду сегодня',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Вы должны приготовить обед: от принесения еды до мытья посуды и наведения порядка. '
                'Если вы не можете выполнить дежурство, перенесите его другому сотруднику. '
                'Если он примет вашу заявку, тогда он выполнит дежурство. '
                'После выполнения отсканируйте QR в офисе — администратор подтвердит.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Открыть раздел дежурства →',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TimeBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFamily: 'Inter')),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontFamily: 'Inter')),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool canCheckIn;
  final bool canCheckOut;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _ActionButtons({
    required this.canCheckIn,
    required this.canCheckOut,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _PressButton(
          label: 'Приход',
          icon: Icons.login_rounded,
          color: AppColors.success,
          enabled: canCheckIn,
          onTap: onCheckIn,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _PressButton(
          label: 'Уход',
          icon: Icons.logout_rounded,
          color: AppColors.error,
          enabled: canCheckOut,
          onTap: onCheckOut,
        ),
      ),
    ]);
  }
}

class _PressButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _PressButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: enabled ? Colors.white : color.withOpacity(0.4),
                size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: enabled ? Colors.white : color.withOpacity(0.4),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'Inter')),
          ],
        ),
      ),
    );
  }
}

// ─── Duty Section (Home) ───────────────────────────────────────────────────────

class _DutySectionHome extends StatelessWidget {
  final List<DutyAssignment> duties;
  final bool loading;
  final String? currentUserId;
  final VoidCallback onOpen;

  const _DutySectionHome({
    required this.duties,
    required this.loading,
    required this.currentUserId,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const _Shimmer(height: 50),
      );
    }

    if (duties.isEmpty) {
      return GestureDetector(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.cleaning_services_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Дежурство сегодня',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter')),
                  SizedBox(height: 4),
                  Text('Дежурного нет',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter')),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ]),
        ),
      );
    }

    return Column(
      children: duties
          .map((duty) => Padding(
                padding: EdgeInsets.only(
                    bottom: duty == duties.last ? 0 : 10),
                child: _DutyCard(
                  duty: duty,
                  isMyDuty: duty.userId == currentUserId,
                  onOpen: onOpen,
                ),
              ))
          .toList(),
    );
  }
}

class _DutyCard extends StatelessWidget {
  final DutyAssignment duty;
  final bool isMyDuty;
  final VoidCallback onOpen;

  const _DutyCard({
    required this.duty,
    required this.isMyDuty,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final isLunch = duty.isLunch;
    final iconData = isLunch ? Icons.lunch_dining_rounded : Icons.cleaning_services_rounded;
    final accentColor = isMyDuty ? AppColors.warning : (isLunch ? AppColors.primary : const Color(0xFF34C759));
    final bgColor = isMyDuty
        ? const Color(0xFFFFFBEB)
        : isLunch
            ? AppColors.primaryLight
            : const Color(0xFFEAF7EC);

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isMyDuty ? const Color(0xFFFFFBEB) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMyDuty ? AppColors.warning : AppColors.border,
            width: isMyDuty ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconData, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${duty.typeEmoji} ${duty.typeLabel} сегодня',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter')),
                const SizedBox(height: 4),
                Text(
                  isMyDuty
                      ? 'Сегодня дежуришь ты!'
                      : duty.userFullName ?? 'Сотрудник',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isMyDuty ? AppColors.warning : AppColors.textPrimary,
                      fontFamily: 'Inter'),
                ),
                if (isMyDuty)
                  const Text('Нажмите, чтобы открыть',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                          fontFamily: 'Inter')),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ]),
      ),
    );
  }
}

// ─── Schedule Mini ─────────────────────────────────────────────────────────────

class _ScheduleMini extends StatelessWidget {
  final List<EmployeeScheduleModel> schedules;
  final bool loading;
  final VoidCallback onTap;

  const _ScheduleMini({
    required this.schedules,
    required this.loading,
    required this.onTap,
  });

  static const _days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  int get _todayDow => DateTime.now().weekday - 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('Мой график',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter')),
                Spacer(),
                Text('Подробнее',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontFamily: 'Inter')),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.primary, size: 16),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const _Shimmer(height: 48)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (dow) {
                  final isToday = dow == _todayDow;
                  final s = _scheduleFor(dow);
                  final isWorking = s?.isWorkingDay ?? false;

                  return Column(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.primary
                            : isWorking
                                ? AppColors.primaryLight
                                : AppColors.divider,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _days[dow],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                              color: isToday
                                  ? Colors.white
                                  : isWorking
                                      ? AppColors.primary
                                      : AppColors.textHint),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isWorking
                          ? (s?.formattedStart?.substring(0, 5) ?? '')
                          : 'Вых',
                      style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Inter',
                          color: isWorking
                              ? AppColors.textSecondary
                              : AppColors.textHint),
                    ),
                  ]);
                }),
              ),
          ],
        ),
      ),
    );
  }

  EmployeeScheduleModel? _scheduleFor(int dow) {
    try {
      return schedules.firstWhere((s) => s.dayOfWeek == dow);
    } catch (_) {
      return null;
    }
  }
}

// ─── News Mini ─────────────────────────────────────────────────────────────────

class _NewsMini extends StatelessWidget {
  final List<News> news;
  final bool loading;
  final VoidCallback onAll;
  final void Function(String id) onItem;

  const _NewsMini({
    required this.news,
    required this.loading,
    required this.onAll,
    required this.onItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Новости',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter')),
            const Spacer(),
            GestureDetector(
              onTap: onAll,
              child: const Row(children: [
                Text('Все',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontFamily: 'Inter')),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.primary, size: 16),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (loading)
            const _Shimmer(height: 80)
          else if (news.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Нет новостей',
                    style: TextStyle(
                        color: AppColors.textHint, fontFamily: 'Inter')),
              ),
            )
          else
            ...news.map((n) => _NewsItem(news: n, onTap: () => onItem(n.id))),
        ],
      ),
    );
  }
}

class _NewsItem extends StatelessWidget {
  final News news;
  final VoidCallback onTap;
  const _NewsItem({required this.news, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(news.title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('d MMM', 'ru').format(news.createdAt),
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontFamily: 'Inter'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(news.content,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                    height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ─── Shimmer placeholder ───────────────────────────────────────────────────────

class _Shimmer extends StatelessWidget {
  final double height;
  const _Shimmer({required this.height});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFEEEEEE),
      highlightColor: const Color(0xFFFAFAFA),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

// ─── Extension ────────────────────────────────────────────────────────────────

extension _Cap on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

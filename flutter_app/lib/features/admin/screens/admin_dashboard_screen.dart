// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/duty_model.dart';
import '../../../core/models/news_model.dart';
import '../../../providers.dart';

// ─── Brand colors ─────────────────────────────────────────────────────────────
const _kBlue1   = Color(0xFF1877F2);
const _kBlue2   = Color(0xFF0D47A1);
const _kTeal1   = Color(0xFF06D6A0);
const _kTeal2   = Color(0xFF059669);
const _kOrange1 = Color(0xFFFF8C42);
const _kOrange2 = Color(0xFFE06920);
const _kPurple1 = Color(0xFF8B5CF6);
const _kPurple2 = Color(0xFF6D28D9);
// _kRed1 / _kRed2 removed — cards now use light pastel style

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const _cacheKey = 'admin_dash_v2';

  // data
  Map<String, dynamic>? _dailyReport;
  Map<String, dynamic>? _weeklyReport;
  List<EmployeeModel>   _employees   = [];
  List<DutyAssignment>  _todayDuties = [];
  List<News>            _news        = [];
  int                   _pendingLeave = 0;

  bool _loading         = true;
  bool _usedCache       = false;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final api  = ref.read(apiServiceProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final weekStart = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 6)));

    // daily
    Map<String, dynamic>? daily;
    bool fromCache = false;
    try {
      daily = await api.getDailyReport(today);
      _saveCache(daily);
    } catch (_) {
      daily = await _loadCache();
      fromCache = daily != null;
    }

    // weekly
    Map<String, dynamic>? weekly;
    try { weekly = await api.getWeeklyReport(weekStart: weekStart); } catch (_) {}

    // employees
    List<EmployeeModel> emps = [];
    try { emps = await api.getEmployees(); } catch (_) {}

    // today duties
    List<DutyAssignment> duties = [];
    try { duties = await api.getTodayDuties(); } catch (_) {}

    // news (count unread)
    List<News> news = [];
    try { news = await api.getNews(); } catch (_) {}

    // pending leave requests
    int pendingLeave = 0;
    try {
      final leaves = await api.getAbsenceRequests(status: 'PENDING');
      pendingLeave = leaves.length;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _dailyReport  = daily;
      _weeklyReport = weekly;
      _employees    = emps;
      _todayDuties  = duties;
      _news         = news;
      _pendingLeave = pendingLeave;
      _usedCache    = fromCache;
      _loading      = false;
    });
    _animCtrl.forward(from: 0);
  }

  Future<void> _saveCache(Map<String, dynamic> data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null) return null;
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return null;
  }

  // ── computed ─────────────────────────────────────────────────────────────────
  int get _totalEmp =>
      _employees.where((e) => !['ADMIN', 'SUPER_ADMIN'].contains(e.role)).length;
  int get _pendingCount =>
      _employees.where((e) => e.status == 'PENDING').length;
  int get _inOffice    => (_dailyReport?['summary']?['in_office_now'] ?? 0) as int;
  int get _lateCount   => (_dailyReport?['summary']?['late'] ?? 0) as int;
  int get _onLeave     => _employees.where((e) => e.status == 'LEAVE').length;
  double get _attendRate =>
      ((_dailyReport?['summary']?['attendance_rate']) as num?)?.toDouble() ?? 0.0;

  String get _dutyPersonName {
    if (_todayDuties.isEmpty) return 'Нет дежурного';
    return _todayDuties.first.userFullName ?? 'Неизвестно';
  }

  List<FlSpot> _weekSpots() {
    final now = DateTime.now();
    final Map<String, int> map = {};
    for (int i = 6; i >= 0; i--) {
      map[DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)))] = 0;
    }
    final days = _weeklyReport?['days'] as Map<String, dynamic>?;
    if (days != null) {
      for (final entry in days.entries) {
        if (map.containsKey(entry.key)) {
          final s = entry.value as Map<String, dynamic>?;
          map[entry.key] = (s?['worked_today'] as int?) ?? 0;
        }
      }
    }
    final list = map.entries.toList();
    return List.generate(list.length, (i) => FlSpot(i.toDouble(), list[i].value.toDouble()));
  }

  // ── build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final firstName = (auth.user?.fullName ?? auth.user?.username ?? 'Администратор')
        .split(' ')
        .first;
    final today = DateFormat('d MMMM, EEEE', 'ru').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kBlue1))
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                onRefresh: _load,
                color: _kBlue1,
                child: CustomScrollView(
                  slivers: [
                    // ── header ──────────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: _Header(
                        firstName: firstName,
                        today: today,
                        pendingCount: _pendingCount,
                        attendRate: _attendRate,
                      ),
                    ),

                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // ── cache banner ──────────────────────────────
                          if (_usedCache) ...[
                            const SizedBox(height: 16),
                            _CacheBanner(onRetry: _load),
                          ],

                          // ── stat cards row ────────────────────────────
                          const SizedBox(height: 20),
                          _StatRow(
                            totalEmp: _totalEmp,
                            inOffice: _inOffice,
                            lateCount: _lateCount,
                            onLeave: _onLeave,
                          ),

                          // ── weekly chart ──────────────────────────────
                          const SizedBox(height: 20),
                          _WeeklyChartCard(spots: _weekSpots()),

                          // ── pending alert ─────────────────────────────
                          if (_pendingCount > 0) ...[
                            const SizedBox(height: 16),
                            _PendingAlert(
                              count: _pendingCount,
                              employees: _employees
                                  .where((e) => e.status == 'PENDING')
                                  .take(3)
                                  .toList(),
                              onApprove: (id) => _approveEmployee(id),
                              onReject:  (id) => _rejectEmployee(id),
                              onSeeAll:  () => context.go('/admin/employees'),
                            ),
                          ],

                          // ── feature cards ─────────────────────────────
                          const SizedBox(height: 12),
                          const _SectionLabel(text: 'Управление'),
                          const SizedBox(height: 12),
                          _FeatureGrid(
                            pendingLeave:  _pendingLeave,
                            dutyPerson:    _dutyPersonName,
                            newsCount:     _news.length,
                            totalEmployees: _totalEmp,
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _approveEmployee(String id) async {
    try {
      await ref.read(apiServiceProvider).updateEmployee(id, {'status': 'ACTIVE'});
      _load();
    } catch (_) {}
  }

  Future<void> _rejectEmployee(String id) async {
    try {
      await ref.read(apiServiceProvider).updateEmployee(id, {'status': 'BLOCKED'});
      _load();
    } catch (_) {}
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String firstName;
  final String today;
  final int    pendingCount;
  final double attendRate;

  const _Header({
    required this.firstName,
    required this.today,
    required this.pendingCount,
    required this.attendRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1877F2), Color(0xFF0A3D91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Привет, $firstName!',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          today,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xBBFFFFFF),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded,
                            color: Colors.white, size: 24),
                      ),
                      if (pendingCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 19,
                            height: 19,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF4757),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── attendance rate bar ─────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Явка сегодня',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${attendRate.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (attendRate / 100).clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        color: _kTeal1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stat Row ─────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final int totalEmp;
  final int inOffice;
  final int lateCount;
  final int onLeave;

  const _StatRow({
    required this.totalEmp,
    required this.inOffice,
    required this.lateCount,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _GradCard(
            value: '$totalEmp',
            label: 'Сотрудников',
            icon: Icons.people_rounded,
            g1: _kBlue1, g2: _kBlue2,
          ),
          const SizedBox(width: 10),
          _GradCard(
            value: '$inOffice',
            label: 'В офисе',
            icon: Icons.business_rounded,
            g1: _kTeal1, g2: _kTeal2,
          ),
          const SizedBox(width: 10),
          _GradCard(
            value: '$lateCount',
            label: 'Опоздали',
            icon: Icons.timer_outlined,
            g1: _kOrange1, g2: _kOrange2,
          ),
          const SizedBox(width: 10),
          _GradCard(
            value: '$onLeave',
            label: 'В отпуске',
            icon: Icons.beach_access_rounded,
            g1: _kPurple1, g2: _kPurple2,
          ),
        ],
      ),
    );
  }
}

class _GradCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color g1, g2;

  const _GradCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.g1,
    required this.g2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [g1, g2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: g1.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFamily: 'Inter',
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xCCFFFFFF),
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Weekly Chart ─────────────────────────────────────────────────────────────

class _WeeklyChartCard extends StatelessWidget {
  final List<FlSpot> spots;

  const _WeeklyChartCard({required this.spots});

  @override
  Widget build(BuildContext context) {
    final now  = DateTime.now();
    final days = List.generate(
        7, (i) => DateFormat('E', 'ru').format(now.subtract(Duration(days: 6 - i))));
    final maxY = spots.isEmpty
        ? 10.0
        : math.max(spots.map((s) => s.y).reduce(math.max) + 2, 5.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: _kBlue1.withValues(alpha: 0.07), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart_rounded, color: _kBlue1, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Посещаемость за неделю',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  Text(
                    'Количество присутствующих по дням',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: spots.isEmpty
                ? const Center(
                    child: Text('Нет данных',
                        style: TextStyle(color: AppColors.textHint, fontFamily: 'Inter')))
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: math.max(maxY / 4, 1),
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: Color(0xFFF0F4FF), strokeWidth: 1.5),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: math.max(maxY / 4, 1),
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textHint,
                                  fontFamily: 'Inter'),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= days.length) return const SizedBox.shrink();
                              final isToday = i == 6;
                              return Text(
                                days[i],
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                                  color: isToday ? _kBlue1 : AppColors.textHint,
                                  fontFamily: 'Inter',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: _kBlue1,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, i) {
                              final isToday = i == spots.length - 1;
                              return FlDotCirclePainter(
                                radius: isToday ? 5 : 3,
                                color: isToday ? _kBlue1 : Colors.white,
                                strokeWidth: 2,
                                strokeColor: _kBlue1,
                              );
                            },
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                _kBlue1.withValues(alpha: 0.18),
                                _kBlue1.withValues(alpha: 0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Pending Alert ────────────────────────────────────────────────────────────

class _PendingAlert extends StatelessWidget {
  final int count;
  final List<EmployeeModel> employees;
  final void Function(String) onApprove;
  final void Function(String) onReject;
  final VoidCallback onSeeAll;

  const _PendingAlert({
    required this.count,
    required this.employees,
    required this.onApprove,
    required this.onReject,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: AppColors.error.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add_rounded, size: 13, color: AppColors.error),
                    const SizedBox(width: 4),
                    Text(
                      '$count новых',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ожидают подтверждения',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                child: const Text(
                  'Все →',
                  style: TextStyle(
                    fontSize: 12,
                    color: _kBlue1,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...employees.map((emp) => _PendingRow(
                emp: emp,
                onApprove: () => onApprove(emp.id),
                onReject:  () => onReject(emp.id),
              )),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final EmployeeModel emp;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingRow({required this.emp, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              emp.fullName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: _kBlue1,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp.fullName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter')),
                Text(emp.email,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        fontFamily: 'Inter')),
              ],
            ),
          ),
          _IconBtn(icon: Icons.close_rounded, color: AppColors.error, bg: AppColors.errorLight, onTap: onReject),
          const SizedBox(width: 6),
          _IconBtn(icon: Icons.check_rounded, color: AppColors.success, bg: AppColors.successLight, onTap: onApprove),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.color, required this.bg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

// ─── Feature Grid ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        fontFamily: 'Inter',
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final int    pendingLeave;
  final String dutyPerson;
  final int    newsCount;
  final int    totalEmployees;

  const _FeatureGrid({
    required this.pendingLeave,
    required this.dutyPerson,
    required this.newsCount,
    required this.totalEmployees,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _FeatureCardData(
        route:     '/admin/employees',
        icon:      Icons.people_alt_rounded,
        label:     'Сотрудники',
        detail:    '$totalEmployees чел.',
        iconColor: _kBlue1,
        iconBg:    const Color(0xFFE8F0FE),
      ),
      const _FeatureCardData(
        route:     '/admin/attendance',
        icon:      Icons.fact_check_rounded,
        label:     'Посещаемость',
        detail:    'Сегодня',
        iconColor: Color(0xFF059669),
        iconBg:    Color(0xFFD1FAE5),
      ),
      _FeatureCardData(
        route:     '/admin/duty',
        icon:      Icons.assignment_ind_rounded,
        label:     'Дежурство',
        detail:    dutyPerson,
        iconColor: _kPurple1,
        iconBg:    const Color(0xFFEDE9FE),
      ),
      _FeatureCardData(
        route:     '/admin/news',
        icon:      Icons.newspaper_rounded,
        label:     'Новости',
        detail:    '$newsCount публикаций',
        iconColor: const Color(0xFF0891B2),
        iconBg:    const Color(0xFFCFFAFE),
      ),
      _FeatureCardData(
        route:     '/admin/requests',
        icon:      Icons.event_note_rounded,
        label:     'Заявки',
        detail:    pendingLeave > 0 ? '$pendingLeave ожидают' : 'Нет новых',
        iconColor: _kOrange1,
        iconBg:    const Color(0xFFFFEDD5),
        badge:     pendingLeave > 0 ? pendingLeave : null,
      ),
      const _FeatureCardData(
        route:     '/admin/qr',
        icon:      Icons.qr_code_2_rounded,
        label:     'QR-коды',
        detail:    'Офисный QR',
        iconColor: Color(0xFFDC2626),
        iconBg:    Color(0xFFFEE2E2),
      ),
      const _FeatureCardData(
        route:     '/admin/reports',
        icon:      Icons.bar_chart_rounded,
        label:     'Отчёты',
        detail:    'Статистика',
        iconColor: Color(0xFF7C3AED),
        iconBg:    Color(0xFFEDE9FE),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (ctx, i) => _FeatureCard(data: cards[i]),
    );
  }
}

class _FeatureCardData {
  final String    route;
  final IconData  icon;
  final String    label;
  final String    detail;
  final Color     iconColor;
  final Color     iconBg;
  final int?      badge;

  const _FeatureCardData({
    required this.route,
    required this.icon,
    required this.label,
    required this.detail,
    required this.iconColor,
    required this.iconBg,
    this.badge,
  });
}

class _FeatureCard extends StatelessWidget {
  final _FeatureCardData data;
  const _FeatureCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(data.route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: data.iconBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(data.icon, color: data.iconColor, size: 22),
                ),
                if (data.badge != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: data.iconBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${data.badge}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: data.iconColor,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cache Banner ─────────────────────────────────────────────────────────────

class _CacheBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _CacheBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Нет сети — показаны последние данные',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter'),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.warning,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Обновить',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

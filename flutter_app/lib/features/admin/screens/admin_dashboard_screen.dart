// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/attendance_model.dart';
import '../../../providers.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  static const _reportCacheKey = 'admin_dashboard_daily_report_v1';

  Map<String, dynamic>? _dailyReport;
  List<EmployeeModel> _employees = [];
  List<AttendanceModel> _weekAttendance = [];
  bool _loading = true;
  bool _usedCachedReport = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final weekStart = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 6)));

    Map<String, dynamic>? report;
    var reportFromCache = false;
    try {
      report = await api.getDailyReport(today);
      await _persistDailyReport(report);
    } catch (_) {
      report = await _loadCachedDailyReport();
      reportFromCache = report != null;
    }

    List<EmployeeModel> emps = _employees;
    try {
      emps = await api.getEmployees();
    } catch (_) {}

    List<AttendanceModel> week = _weekAttendance;
    try {
      week = await api.getAllAttendance(startDate: weekStart, endDate: today);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _dailyReport = report;
      _employees = emps;
      _weekAttendance = week;
      _usedCachedReport = reportFromCache;
      _loading = false;
    });
  }

  Future<void> _persistDailyReport(Map<String, dynamic> report) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_reportCacheKey, jsonEncode(report));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCachedDailyReport() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_reportCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }

  int get _totalEmployees =>
      _employees.where((e) => !['ADMIN', 'SUPER_ADMIN'].contains(e.role)).length;
  int get _pendingCount =>
      _employees.where((e) => e.status == 'PENDING').length;

  Map<String, dynamic>? get _summary {
    if (_dailyReport == null) return null;
    return _dailyReport!['summary'] as Map<String, dynamic>?;
  }

  List<FlSpot> _buildChartSpots() {
    final now = DateTime.now();
    final Map<String, int> presentByDay = {};
    for (int i = 6; i >= 0; i--) {
      final d = DateFormat('yyyy-MM-dd')
          .format(now.subtract(Duration(days: i)));
      presentByDay[d] = 0;
    }
    for (final rec in _weekAttendance) {
      final date = rec.date.substring(0, 10);
      if (presentByDay.containsKey(date)) {
        if (rec.status == 'PRESENT' ||
            rec.status == 'LATE' ||
            rec.status == 'OVERTIME') {
          presentByDay[date] = (presentByDay[date] ?? 0) + 1;
        }
      }
    }
    final entries = presentByDay.entries.toList();
    return List.generate(
      entries.length,
      (i) => FlSpot(i.toDouble(), entries[i].value.toDouble()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final adminName = auth.user?.fullName ?? auth.user?.username ?? 'Администратор';
    final today = DateFormat('d MMMM, EEEE', 'ru').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(adminName, today)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (_usedCachedReport)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _CacheBanner(onRetry: _load),
                          ),
                        _buildStatCards(),
                        const SizedBox(height: 20),
                        _buildChartCard(),
                        const SizedBox(height: 20),
                        _buildQuickActions(context),
                        if (_pendingCount > 0) ...[
                          const SizedBox(height: 20),
                          _buildPendingSection(),
                        ],
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(String name, String today) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1877F2), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Привет, ${name.split(' ').first}!',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      today,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xCCFFFFFF),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 22),
                  ),
                  if (_pendingCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4757),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$_pendingCount',
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
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    final s = _summary;
    // API: present = завершили день (приход+уход); in_office_now = без отметки ухода
    final inOfficeNow = s?['in_office_now'] ?? 0;
    final late = s?['late'] ?? 0;
    final onLeave = _employees.where((e) => e.status == 'LEAVE').length;

    return Row(
      children: [
        _StatCard(
          value: '$_totalEmployees',
          label: 'Всего',
          icon: Icons.people_rounded,
          color: AppColors.primary,
          bg: AppColors.primaryLight,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: '$inOfficeNow',
          label: 'В офисе',
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          bg: AppColors.successLight,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: '$late',
          label: 'Опоздали',
          icon: Icons.timer_outlined,
          color: AppColors.warning,
          bg: AppColors.warningLight,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: '$onLeave',
          label: 'В отпуске',
          icon: Icons.beach_access_rounded,
          color: AppColors.purple,
          bg: AppColors.purpleLight,
        ),
      ],
    );
  }

  Widget _buildChartCard() {
    final spots = _buildChartSpots();
    final now = DateTime.now();
    final days = List.generate(
        7, (i) => DateFormat('E', 'ru').format(now.subtract(Duration(days: 6 - i))));

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
          Row(
            children: [
              const Text(
                'Посещаемость за неделю',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '7 дней',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: spots.isEmpty
                ? const Center(
                    child: Text('Нет данных',
                        style: TextStyle(
                            color: AppColors.textHint, fontFamily: 'Inter')))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 2,
                        getDrawingHorizontalLine: (v) => const FlLine(
                          color: AppColors.divider,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 2,
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
                              if (i < 0 || i >= days.length) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                days[i],
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textHint,
                                    fontFamily: 'Inter'),
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
                          color: AppColors.primary,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, ___) =>
                                FlDotCirclePainter(
                              radius: 3.5,
                              color: AppColors.primary,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withOpacity(0.18),
                                AppColors.primary.withOpacity(0.0),
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

  Widget _buildQuickActions(BuildContext context) {
    final tiles = <_QuickTile>[
      _QuickTile(
        icon: Icons.assignment_ind_rounded,
        label: 'Дежурство',
        color: AppColors.purple,
        bg: AppColors.purpleLight,
        onTap: () => context.push('/admin/duty'),
      ),
      _QuickTile(
        icon: Icons.article_rounded,
        label: 'Новости',
        color: AppColors.primary,
        bg: AppColors.primaryLight,
        onTap: () => context.push('/admin/news'),
      ),
      _QuickTile(
        icon: Icons.event_note_rounded,
        label: 'Заявки',
        color: AppColors.warning,
        bg: AppColors.warningLight,
        onTap: () => context.push('/admin/requests'),
      ),
      _QuickTile(
        icon: Icons.qr_code_rounded,
        label: 'QR',
        color: AppColors.success,
        bg: AppColors.successLight,
        onTap: () => context.push('/admin/qr'),
      ),
      _QuickTile(
        icon: Icons.fact_check_rounded,
        label: 'Посещаемость',
        color: AppColors.primary,
        bg: AppColors.primaryLight,
        onTap: () => context.go('/admin/attendance'),
      ),
      _QuickTile(
        icon: Icons.router_rounded,
        label: 'Сети',
        color: AppColors.textSecondary,
        bg: AppColors.divider,
        onTap: () => context.push('/admin/networks'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Быстрые действия',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, i) {
            final t = tiles[i];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: t.onTap,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: t.bg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(t.icon, color: t.color, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPendingSection() {
    final pending =
        _employees.where((e) => e.status == 'PENDING').take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_pendingCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Ожидают подтверждения',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/admin/employees'),
                child: const Text(
                  'Все →',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...pending.map((emp) => _PendingItem(
                emp: emp,
                onApprove: () => _approveEmployee(emp.id),
                onReject: () => _rejectEmployee(emp.id),
              )),
        ],
      ),
    );
  }

  Future<void> _approveEmployee(String id) async {
    try {
      await ref
          .read(apiServiceProvider)
          .updateEmployee(id, {'status': 'ACTIVE'});
      _load();
    } catch (_) {}
  }

  Future<void> _rejectEmployee(String id) async {
    try {
      await ref
          .read(apiServiceProvider)
          .updateEmployee(id, {'status': 'BLOCKED'});
      _load();
    } catch (_) {}
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Inter',
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textHint,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTile {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });
}

class _CacheBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _CacheBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppColors.warning, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Нет сети: показана последняя сохранённая сводка за день.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }
}

// ─── Pending Item ─────────────────────────────────────────────────────────────

class _PendingItem extends StatelessWidget {
  final EmployeeModel emp;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingItem({
    required this.emp,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                emp.fullName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              emp.fullName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          GestureDetector(
            onTap: onReject,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppColors.error, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onApprove,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.success, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

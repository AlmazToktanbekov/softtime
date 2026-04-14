// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/attendance_model.dart';
import '../../../core/models/user_model.dart';
import '../../../providers.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  bool _isWeekly = true;
  bool _loading = true;
  List<AttendanceModel> _records = [];
  List<EmployeeModel> _employees = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final now = DateTime.now();
      final endDate = DateFormat('yyyy-MM-dd').format(now);
      final startDate = _isWeekly
          ? DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 6)))
          : DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));

      final results = await Future.wait([
        api.getAllAttendance(startDate: startDate, endDate: endDate),
        api.getEmployees(),
      ]);

      if (!mounted) return;
      setState(() {
        _records = results[0] as List<AttendanceModel>;
        _employees = (results[1] as List<EmployeeModel>)
            .where((e) => !['ADMIN', 'SUPER_ADMIN'].contains(e.role))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Count status occurrences
  Map<String, int> get _statusCounts {
    final counts = <String, int>{};
    for (final r in _records) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }
    return counts;
  }

  // Per-employee hours
  List<_EmployeeStat> get _employeeStats {
    final Map<String, _EmployeeStat> stats = {};
    for (final r in _records) {
      if (!stats.containsKey(r.userId)) {
        final name = _findName(r.userId);
        stats[r.userId] = _EmployeeStat(id: r.userId, name: name);
      }
      final s = stats[r.userId]!;
      if (r.checkInTime != null && r.checkOutTime != null) {
        try {
          final inDt = DateTime.parse(r.checkInTime!);
          final outDt = DateTime.parse(r.checkOutTime!);
          s.totalMinutes += outDt.difference(inDt).inMinutes;
        } catch (_) {}
      }
      if (r.status == 'LATE') s.lateCount++;
      if (r.status == 'ABSENT' || r.status == 'INCOMPLETE') s.absentCount++;
    }
    return stats.values.toList()
      ..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));
  }

  String _findName(String userId) {
    try {
      return _employees.firstWhere((e) => e.id == userId).fullName;
    } catch (_) {
      return userId.substring(0, 8);
    }
  }

  // Build daily spots for line chart
  List<FlSpot> _buildChartSpots() {
    final now = DateTime.now();
    final days = _isWeekly ? 7 : now.day;
    final Map<String, int> countByDay = {};
    for (int i = days - 1; i >= 0; i--) {
      final d = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)));
      countByDay[d] = 0;
    }
    for (final r in _records) {
      final date = r.date.substring(0, 10);
      if (countByDay.containsKey(date)) {
        if (['PRESENT', 'LATE', 'OVERTIME'].contains(r.status)) {
          countByDay[date] = (countByDay[date] ?? 0) + 1;
        }
      }
    }
    final entries = countByDay.entries.toList();
    return List.generate(
        entries.length, (i) => FlSpot(i.toDouble(), entries[i].value.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Отчёты'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Period toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _PeriodTab(
                    label: 'Неделя',
                    isActive: _isWeekly,
                    onTap: () {
                      if (!_isWeekly) {
                        setState(() => _isWeekly = true);
                        _load();
                      }
                    },
                  ),
                  _PeriodTab(
                    label: 'Месяц',
                    isActive: !_isWeekly,
                    onTap: () {
                      if (_isWeekly) {
                        setState(() => _isWeekly = false);
                        _load();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildSummaryCards(),
                        const SizedBox(height: 16),
                        _buildLineChartCard(),
                        const SizedBox(height: 16),
                        _buildStatusDistribution(),
                        const SizedBox(height: 16),
                        _buildTopEmployees(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final counts = _statusCounts;
    final present = (counts['PRESENT'] ?? 0) + (counts['LATE'] ?? 0) + (counts['OVERTIME'] ?? 0);
    final late = counts['LATE'] ?? 0;
    final absent = (counts['ABSENT'] ?? 0) + (counts['INCOMPLETE'] ?? 0);
    final approved = counts['APPROVED_ABSENCE'] ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _GridStatCard(
            value: '$present',
            label: 'Явки',
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            bg: AppColors.successLight),
        _GridStatCard(
            value: '$late',
            label: 'Опоздания',
            icon: Icons.timer_outlined,
            color: AppColors.warning,
            bg: AppColors.warningLight),
        _GridStatCard(
            value: '$absent',
            label: 'Пропуски',
            icon: Icons.cancel_rounded,
            color: AppColors.error,
            bg: AppColors.errorLight),
        _GridStatCard(
            value: '$approved',
            label: 'Уважительные',
            icon: Icons.verified_user_rounded,
            color: AppColors.purple,
            bg: AppColors.purpleLight),
      ],
    );
  }

  Widget _buildLineChartCard() {
    final spots = _buildChartSpots();
    final now = DateTime.now();
    final days = _isWeekly ? 7 : now.day;
    final labels = List.generate(days, (i) {
      final d = now.subtract(Duration(days: days - 1 - i));
      return _isWeekly
          ? DateFormat('E', 'ru').format(d)
          : DateFormat('d', 'ru').format(d);
    });

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
          Text(
            _isWeekly ? 'Посещаемость за неделю' : 'Посещаемость за месяц',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
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
                        getDrawingHorizontalLine: (v) =>
                            const FlLine(color: AppColors.divider, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 3,
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
                            reservedSize: 20,
                            interval: _isWeekly ? 1 : 5,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= labels.length) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                labels[i],
                                style: const TextStyle(
                                    fontSize: 9,
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
                            getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                              radius: 3,
                              color: AppColors.primary,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withOpacity(0.15),
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

  Widget _buildStatusDistribution() {
    final counts = _statusCounts;
    if (counts.isEmpty) return const SizedBox.shrink();

    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final present =
        ((counts['PRESENT'] ?? 0) + (counts['LATE'] ?? 0) + (counts['OVERTIME'] ?? 0)) /
            total *
            100;
    final absent =
        ((counts['ABSENT'] ?? 0) + (counts['INCOMPLETE'] ?? 0)) / total * 100;
    final approved = (counts['APPROVED_ABSENCE'] ?? 0) / total * 100;
    final other = 100 - present - absent - approved;

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
          const Text(
            'Распределение статусов',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: present,
                        color: AppColors.success,
                        radius: 46,
                        title: '',
                      ),
                      PieChartSectionData(
                        value: absent,
                        color: AppColors.error,
                        radius: 46,
                        title: '',
                      ),
                      PieChartSectionData(
                        value: approved,
                        color: AppColors.purple,
                        radius: 46,
                        title: '',
                      ),
                      if (other > 0)
                        PieChartSectionData(
                          value: other,
                          color: AppColors.divider,
                          radius: 46,
                          title: '',
                        ),
                    ],
                    centerSpaceRadius: 28,
                    sectionsSpace: 2,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(
                        color: AppColors.success,
                        label: 'Присутствие',
                        value: '${present.toStringAsFixed(0)}%'),
                    const SizedBox(height: 8),
                    _LegendItem(
                        color: AppColors.error,
                        label: 'Пропуски',
                        value: '${absent.toStringAsFixed(0)}%'),
                    const SizedBox(height: 8),
                    _LegendItem(
                        color: AppColors.purple,
                        label: 'Уважительные',
                        value: '${approved.toStringAsFixed(0)}%'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopEmployees() {
    final stats = _employeeStats.take(5).toList();
    if (stats.isEmpty) return const SizedBox.shrink();

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
          const Text(
            'Топ по рабочим часам',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(stats.length, (i) {
            final s = stats[i];
            final hours = s.totalMinutes ~/ 60;
            final mins = s.totalMinutes % 60;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? const Color(0xFFFFF8E1)
                          : AppColors.divider,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: i == 0
                              ? const Color(0xFFFFB300)
                              : AppColors.textHint,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        Row(
                          children: [
                            if (s.lateCount > 0) ...[
                              Text(
                                'Опоздания: ${s.lateCount}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.warning,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (s.absentCount > 0)
                              Text(
                                'Пропуски: ${s.absentCount}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.error,
                                  fontFamily: 'Inter',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${hours}ч ${mins}м', // ignore: unnecessary_brace_in_string_interps
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PeriodTab(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.textHint,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;

  const _GridStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textHint,
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

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem(
      {required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

class _EmployeeStat {
  final String id;
  final String name;
  int totalMinutes = 0;
  int lateCount = 0;
  int absentCount = 0;

  _EmployeeStat({required this.id, required this.name});
}

// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Отчёты'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          tabs: const [
            Tab(text: 'День'),
            Tab(text: 'Неделя'),
            Tab(text: 'Месяц'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _DailyTab(),
          _WeeklyTab(),
          _MonthlyTab(),
        ],
      ),
    );
  }
}

// ─── DAILY TAB ────────────────────────────────────────────────────────────────

class _DailyTab extends ConsumerStatefulWidget {
  const _DailyTab();

  @override
  ConsumerState<_DailyTab> createState() => _DailyTabState();
}

class _DailyTabState extends ConsumerState<_DailyTab> {
  DateTime _date = DateTime.now();
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(_date);
      final data = await api.getDailyReport(dateStr);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (picked != null && picked != _date) {
      setState(() => _date = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _data?['summary'] as Map<String, dynamic>?;
    final detail = (_data?['detail'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      children: [
        _DatePickerBar(
          label: DateFormat('d MMMM yyyy', 'ru').format(_date),
          onPrev: () {
            setState(() => _date = _date.subtract(const Duration(days: 1)));
            _load();
          },
          onNext: _date.day == DateTime.now().day &&
                  _date.month == DateTime.now().month
              ? null
              : () {
                  setState(() => _date = _date.add(const Duration(days: 1)));
                  _load();
                },
          onPick: _pickDate,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _data == null
                      ? const SizedBox.shrink()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.primary,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (summary != null) ...[
                                _SummaryGrid(summary: summary),
                                const SizedBox(height: 16),
                              ],
                              if (detail.isNotEmpty) ...[
                                _SectionTitle(
                                    title: 'Посещаемость сотрудников',
                                    count: detail.length),
                                const SizedBox(height: 8),
                                _DailyDetailTable(rows: detail),
                              ] else
                                const _EmptyCard(
                                    text: 'Нет данных за выбранный день'),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
        ),
      ],
    );
  }
}

// ─── WEEKLY TAB ───────────────────────────────────────────────────────────────

class _WeeklyTab extends ConsumerStatefulWidget {
  const _WeeklyTab();

  @override
  ConsumerState<_WeeklyTab> createState() => _WeeklyTabState();
}

class _WeeklyTabState extends ConsumerState<_WeeklyTab> {
  late DateTime _weekStart;
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(_weekStart);
      final data = await api.getWeeklyReport(weekStart: dateStr);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final label =
        '${DateFormat('d MMM', 'ru').format(_weekStart)} — ${DateFormat('d MMM yyyy', 'ru').format(weekEnd)}';

    final days = (_data?['days'] as Map<String, dynamic>?) ?? {};

    return Column(
      children: [
        _DatePickerBar(
          label: label,
          onPrev: () {
            setState(() =>
                _weekStart = _weekStart.subtract(const Duration(days: 7)));
            _load();
          },
          onNext: _weekStart
                      .add(const Duration(days: 7))
                      .isAfter(DateTime.now())
              ? null
              : () {
                  setState(() =>
                      _weekStart = _weekStart.add(const Duration(days: 7)));
                  _load();
                },
          onPick: null,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _data == null
                      ? const SizedBox.shrink()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.primary,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _WeeklyLineChart(days: days, weekStart: _weekStart),
                              const SizedBox(height: 16),
                              _WeeklyDayCards(days: days, weekStart: _weekStart),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
        ),
      ],
    );
  }
}

// ─── MONTHLY TAB ──────────────────────────────────────────────────────────────

class _MonthlyTab extends ConsumerStatefulWidget {
  const _MonthlyTab();

  @override
  ConsumerState<_MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends ConsumerState<_MonthlyTab> {
  late int _year;
  late int _month;
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;
  String _sortKey = 'days_present';
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getMonthlyReport(_year, _month);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year == now.year && _month == now.month) return;
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  void _openEmployeeDetail(Map<String, dynamic> emp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeDetailSheet(
        userId: emp['user_id'] as String,
        fullName: emp['full_name'] as String? ?? '',
        year: _year,
        month: _month,
        apiRef: ref,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy', 'ru')
        .format(DateTime(_year, _month))
        .replaceFirst(
            DateFormat('MMMM', 'ru').format(DateTime(_year, _month)),
            DateFormat('MMMM', 'ru')
                .format(DateTime(_year, _month))
                .capitalize());

    final summary = _data?['summary'] as Map<String, dynamic>?;
    final employees =
        ((_data?['employees']) as List?)?.cast<Map<String, dynamic>>() ?? [];

    final sorted = List<Map<String, dynamic>>.from(employees);
    sorted.sort((a, b) {
      final av = a[_sortKey] as num? ?? 0;
      final bv = b[_sortKey] as num? ?? 0;
      return _sortDesc ? bv.compareTo(av) : av.compareTo(bv);
    });

    return Column(
      children: [
        _DatePickerBar(
          label: label,
          onPrev: _prevMonth,
          onNext: _isCurrentMonth ? null : _nextMonth,
          onPick: null,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _data == null
                      ? const SizedBox.shrink()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.primary,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (summary != null) ...[
                                _SummaryGrid(summary: summary),
                                const SizedBox(height: 16),
                              ],
                              if (sorted.isNotEmpty) ...[
                                _SectionTitle(
                                    title: 'Сотрудники',
                                    count: sorted.length),
                                const SizedBox(height: 4),
                                _SortBar(
                                  sortKey: _sortKey,
                                  sortDesc: _sortDesc,
                                  onSort: (key) {
                                    setState(() {
                                      if (_sortKey == key) {
                                        _sortDesc = !_sortDesc;
                                      } else {
                                        _sortKey = key;
                                        _sortDesc = true;
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                ...sorted.map((emp) => _MonthlyEmployeeCard(
                                      emp: emp,
                                      onTap: () => _openEmployeeDetail(emp),
                                    )),
                              ] else
                                const _EmptyCard(
                                    text: 'Нет данных за выбранный месяц'),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
        ),
      ],
    );
  }
}

// ─── EMPLOYEE DETAIL BOTTOM SHEET ─────────────────────────────────────────────

class _EmployeeDetailSheet extends ConsumerStatefulWidget {
  final String userId;
  final String fullName;
  final int year;
  final int month;
  final WidgetRef apiRef;

  const _EmployeeDetailSheet({
    required this.userId,
    required this.fullName,
    required this.year,
    required this.month,
    required this.apiRef,
  });

  @override
  ConsumerState<_EmployeeDetailSheet> createState() =>
      _EmployeeDetailSheetState();
}

class _EmployeeDetailSheetState extends ConsumerState<_EmployeeDetailSheet> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = widget.apiRef.read(apiServiceProvider);
      final start = '${widget.year}-${widget.month.toString().padLeft(2, '0')}-01';
      final lastDay = DateTime(widget.year, widget.month + 1, 0).day;
      final end =
          '${widget.year}-${widget.month.toString().padLeft(2, '0')}-$lastDay';
      final data =
          await api.getEmployeeReport(widget.userId, startDate: start, endDate: end);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _data?['stats'] as Map<String, dynamic>?;
    final records =
        ((_data?['records']) as List?)?.cast<Map<String, dynamic>>() ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textHint),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? _ErrorView(message: _error!, onRetry: _load)
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            if (stats != null) ...[
                              _EmployeeStatRow(stats: stats),
                              const SizedBox(height: 16),
                            ],
                            if (records.isNotEmpty) ...[
                              const _SectionTitle(
                                  title: 'История посещаемости'),
                              const SizedBox(height: 8),
                              ...records.map((r) => _AttendanceRecordTile(r: r)),
                            ] else
                              const _EmptyCard(text: 'Нет записей'),
                            const SizedBox(height: 24),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── REUSABLE COMPONENTS ──────────────────────────────────────────────────────

class _DatePickerBar extends StatelessWidget {
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onPick;

  const _DatePickerBar({
    required this.label,
    this.onPrev,
    this.onNext,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: onPrev != null ? AppColors.textPrimary : AppColors.border,
            onPressed: onPrev,
          ),
          GestureDetector(
            onTap: onPick,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                if (onPick != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded,
                      size: 18, color: AppColors.textHint),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: onNext != null ? AppColors.textPrimary : AppColors.border,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final Map<String, dynamic> summary;

  const _SummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = summary['total_employees'] as int? ?? 0;
    final workedToday = (summary['worked_today'] as int?) ?? (summary['present'] as int?) ?? 0;
    final inOffice = summary['in_office_now'] as int? ?? 0;
    final late = summary['late'] as int? ?? 0;
    final absent = summary['absent'] as int? ?? 0;
    final rate = summary['attendance_rate'] as double? ?? 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '$workedToday / $total',
                label: 'Пришли',
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                bg: AppColors.successLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: '${rate.toStringAsFixed(0)}%',
                label: 'Явка',
                icon: Icons.trending_up_rounded,
                color: AppColors.primary,
                bg: AppColors.primaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '$late',
                label: 'Опоздали',
                icon: Icons.timer_outlined,
                color: AppColors.warning,
                bg: AppColors.warningLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: '$absent',
                label: 'Отсутствуют',
                icon: Icons.cancel_rounded,
                color: AppColors.error,
                bg: AppColors.errorLight,
              ),
            ),
          ],
        ),
        if (inOffice > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.business_rounded,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Сейчас в офисе: $inOffice чел.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
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
        ],
      ),
    );
  }
}

class _DailyDetailTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _DailyDetailTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: _HeaderCell(text: 'Сотрудник')),
                Expanded(child: _HeaderCell(text: 'Приход')),
                Expanded(child: _HeaderCell(text: 'Уход')),
                Expanded(child: _HeaderCell(text: 'Статус')),
              ],
            ),
          ),
          ...rows.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            return Container(
              decoration: BoxDecoration(
                border: i < rows.length - 1
                    ? const Border(
                        bottom: BorderSide(color: AppColors.divider))
                    : null,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['employee_name'] as String? ?? '—',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((r['late_minutes'] as int? ?? 0) > 0)
                          Text(
                            '+${r['late_minutes']}мин',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.warning,
                              fontFamily: 'Inter',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r['check_in_time'] as String? ?? '—',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter'),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r['check_out_time'] as String? ?? '—',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter'),
                    ),
                  ),
                  Expanded(
                    child: _StatusBadge(
                        status: r['status'] as String? ?? ''),
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

class _WeeklyLineChart extends StatelessWidget {
  final Map<String, dynamic> days;
  final DateTime weekStart;

  const _WeeklyLineChart({required this.days, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final dates = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    List<FlSpot> spots(String field) => dates.asMap().entries.map((e) {
          final key = DateFormat('yyyy-MM-dd').format(e.value);
          final summary = days[key] as Map<String, dynamic>?;
          return FlSpot(
              e.key.toDouble(), (summary?[field] as int? ?? 0).toDouble());
        }).toList();

    final presentSpots = spots('present');
    final lateSpots = spots('late');
    final absentSpots = spots('absent');

    final maxVal = [presentSpots, lateSpots, absentSpots]
        .expand((s) => s)
        .map((s) => s.y)
        .fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Посещаемость по дням',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 6),
          // Легенда
          Row(
            children: [
              _LegendDot(color: AppColors.success, label: 'Пришли'),
              const SizedBox(width: 14),
              _LegendDot(color: AppColors.warning, label: 'Опоздали'),
              const SizedBox(width: 14),
              _LegendDot(color: AppColors.error, label: 'Отсутствие'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxVal < 1 ? 5 : maxVal + 2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppColors.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: maxVal > 0 ? (maxVal / 4).ceilToDouble() : 1,
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
                        if (i < 0 || i >= dates.length) {
                          return const SizedBox.shrink();
                        }
                        final isToday = dates[i].day == DateTime.now().day &&
                            dates[i].month == DateTime.now().month;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('E', 'ru').format(dates[i]),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isToday
                                  ? AppColors.primary
                                  : AppColors.textHint,
                              fontFamily: 'Inter',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textPrimary,
                    getTooltipItems: (spots) => spots.map((s) {
                      final labels = ['Пришли', 'Опоздали', 'Отсутствие'];
                      final colors = [
                        AppColors.success,
                        AppColors.warning,
                        AppColors.error
                      ];
                      return LineTooltipItem(
                        '${labels[s.barIndex]}: ${s.y.toInt()}',
                        TextStyle(
                          color: colors[s.barIndex],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  _line(presentSpots, AppColors.success),
                  _line(lateSpots, AppColors.warning),
                  _line(absentSpots, AppColors.error),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.35,
        color: color,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
            radius: 3.5,
            color: color,
            strokeWidth: 2,
            strokeColor: Colors.white,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          color: color.withOpacity(0.08),
        ),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
              fontSize: 11, color: AppColors.textHint, fontFamily: 'Inter'),
        ),
      ],
    );
  }
}

class _WeeklyDayCards extends StatelessWidget {
  final Map<String, dynamic> days;
  final DateTime weekStart;

  const _WeeklyDayCards({required this.days, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'По дням'),
        const SizedBox(height: 8),
        ...List.generate(7, (i) {
          final d = weekStart.add(Duration(days: i));
          final key = DateFormat('yyyy-MM-dd').format(d);
          final summary = days[key] as Map<String, dynamic>?;
          if (summary == null) return const SizedBox.shrink();
          final present = summary['present'] as int? ?? 0;
          final late = summary['late'] as int? ?? 0;
          final absent = summary['absent'] as int? ?? 0;
          final total = summary['total_employees'] as int? ?? 0;
          final isToday = d.day == DateTime.now().day &&
              d.month == DateTime.now().month;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isToday ? AppColors.primary : AppColors.border,
                  width: isToday ? 1.5 : 1),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('E', 'ru').format(d).toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isToday
                              ? AppColors.primary
                              : AppColors.textHint,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        DateFormat('d').format(d),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isToday
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 36, color: AppColors.divider),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MiniStat(
                          value: '$present/$total',
                          label: 'Пришли',
                          color: AppColors.success),
                      _MiniStat(
                          value: '$late',
                          label: 'Опоздали',
                          color: AppColors.warning),
                      _MiniStat(
                          value: '$absent',
                          label: 'Отсутствие',
                          color: AppColors.error),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _MonthlyEmployeeCard extends StatelessWidget {
  final Map<String, dynamic> emp;
  final VoidCallback onTap;

  const _MonthlyEmployeeCard({required this.emp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = emp['full_name'] as String? ?? '—';
    final team = emp['team_name'] as String?;
    final daysPresent = emp['days_present'] as int? ?? 0;
    final daysLate = emp['days_late'] as int? ?? 0;
    final daysAbsent = emp['days_absent'] as int? ?? 0;
    final workMin = emp['total_work_minutes'] as int? ?? 0;
    final workH = workMin ~/ 60;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (team != null)
                    Text(
                      team,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                          fontFamily: 'Inter'),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MonthBadge(
                    value: '$daysPresent',
                    label: 'дней',
                    color: AppColors.success),
                const SizedBox(width: 6),
                if (daysLate > 0)
                  _MonthBadge(
                      value: '$daysLate',
                      label: 'опозд',
                      color: AppColors.warning),
                if (daysAbsent > 0) ...[
                  const SizedBox(width: 6),
                  _MonthBadge(
                      value: '$daysAbsent',
                      label: 'пропуск',
                      color: AppColors.error),
                ],
                const SizedBox(width: 6),
                _MonthBadge(
                    value: '${workH}ч', // ignore: unnecessary_brace_in_string_interps
                    label: 'всего',
                    color: AppColors.primary),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _EmployeeStatRow extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _EmployeeStatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final daysPresent = stats['days_present'] as int? ?? 0;
    final daysLate = stats['days_late'] as int? ?? 0;
    final lateMins = stats['total_late_minutes'] as int? ?? 0;
    final workMins = stats['total_work_minutes'] as int? ?? 0;
    final workH = workMins ~/ 60;
    final workM = workMins % 60;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _EmpStatItem(value: '$daysPresent', label: 'Дней\nприсутствия'),
          _EmpStatItem(value: '$daysLate', label: 'Дней\nопозданий'),
          _EmpStatItem(
              value: '${lateMins}м', // ignore: unnecessary_brace_in_string_interps
              label: 'Всего\nопоздал'),
          _EmpStatItem(
              value: '${workH}ч ${workM}м', // ignore: unnecessary_brace_in_string_interps
              label: 'Рабочие\nчасы'),
        ],
      ),
    );
  }
}

class _AttendanceRecordTile extends StatelessWidget {
  final Map<String, dynamic> r;

  const _AttendanceRecordTile({required this.r});

  @override
  Widget build(BuildContext context) {
    final date = r['date'] as String? ?? '';
    final checkIn = r['check_in'] as String?;
    final checkOut = r['check_out'] as String?;
    final status = r['status'] as String? ?? '';
    final lateMin = r['late_minutes'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                if (lateMin > 0)
                  Text(
                    '+${lateMin}мин', // ignore: unnecessary_brace_in_string_interps
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.warning,
                        fontFamily: 'Inter'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              checkIn ?? '—',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter'),
            ),
          ),
          Expanded(
            child: Text(
              checkOut ?? '—',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter'),
            ),
          ),
          _StatusBadge(status: status),
        ],
      ),
    );
  }

  String _formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      return DateFormat('d MMM', 'ru').format(d);
    } catch (_) {
      return date;
    }
  }
}

class _SortBar extends StatelessWidget {
  final String sortKey;
  final bool sortDesc;
  final ValueChanged<String> onSort;

  const _SortBar({
    required this.sortKey,
    required this.sortDesc,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SortChip(
            label: 'Присутствие',
            sortKey: 'days_present',
            currentKey: sortKey,
            sortDesc: sortDesc,
            onSort: onSort,
          ),
          const SizedBox(width: 6),
          _SortChip(
            label: 'Опоздания',
            sortKey: 'days_late',
            currentKey: sortKey,
            sortDesc: sortDesc,
            onSort: onSort,
          ),
          const SizedBox(width: 6),
          _SortChip(
            label: 'Часы',
            sortKey: 'total_work_minutes',
            currentKey: sortKey,
            sortDesc: sortDesc,
            onSort: onSort,
          ),
          const SizedBox(width: 6),
          _SortChip(
            label: 'Пропуски',
            sortKey: 'days_absent',
            currentKey: sortKey,
            sortDesc: sortDesc,
            onSort: onSort,
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final String sortKey;
  final String currentKey;
  final bool sortDesc;
  final ValueChanged<String> onSort;

  const _SortChip({
    required this.label,
    required this.sortKey,
    required this.currentKey,
    required this.sortDesc,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sortKey == currentKey;
    return GestureDetector(
      onTap: () => onSort(sortKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.white : AppColors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                sortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                size: 12,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'PRESENT' => ('Пришёл', AppColors.success, AppColors.successLight),
      'LATE' => ('Опоздал', AppColors.warning, AppColors.warningLight),
      'ABSENT' => ('Отсутствие', AppColors.error, AppColors.errorLight),
      'INCOMPLETE' => ('Неполный', AppColors.warning, AppColors.warningLight),
      'APPROVED_ABSENCE' => ('Уважит.', AppColors.purple, AppColors.purpleLight),
      'OVERTIME' => ('Сверхур.', AppColors.primary, AppColors.primaryLight),
      'EARLY_LEAVE' => ('Ранний уход', AppColors.warning, AppColors.warningLight),
      'MANUAL' => ('Вручную', AppColors.textHint, AppColors.background),
      _ => (status, AppColors.textHint, AppColors.background),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int? count;

  const _SectionTitle({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
              color: AppColors.textHint, fontSize: 14, fontFamily: 'Inter'),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontFamily: 'Inter'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textHint,
        fontFamily: 'Inter',
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _MiniStat(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'Inter',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
              fontSize: 10, color: AppColors.textHint, fontFamily: 'Inter'),
        ),
      ],
    );
  }
}

class _MonthBadge extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _MonthBadge(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'Inter',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
              fontSize: 9, color: AppColors.textHint, fontFamily: 'Inter'),
        ),
      ],
    );
  }
}

class _EmpStatItem extends StatelessWidget {
  final String value;
  final String label;

  const _EmpStatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            fontFamily: 'Inter',
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontFamily: 'Inter'),
        ),
      ],
    );
  }
}

extension on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);
}

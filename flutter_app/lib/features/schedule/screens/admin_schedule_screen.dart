// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/user_model.dart';
import '../../../providers.dart';
import '../../../core/theme/app_theme.dart';

class AdminScheduleScreen extends ConsumerStatefulWidget {
  const AdminScheduleScreen({super.key});

  @override
  ConsumerState<AdminScheduleScreen> createState() =>
      _AdminScheduleScreenState();
}

class _AdminScheduleScreenState extends ConsumerState<AdminScheduleScreen> {
  List<EmployeeModel> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(apiServiceProvider).getEmployees();
      if (mounted) setState(() => _employees = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Расписание сотрудников'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : _employees.isEmpty
              ? const Center(
                  child: Text(
                    'Нет активных сотрудников',
                    style: TextStyle(
                      color: AppColors.textHint,
                      fontFamily: 'Inter',
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _employees.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) => _EmployeeScheduleTile(
                      employee: _employees[i],
                    ),
                  ),
                ),
    );
  }

  Widget _buildShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─── Employee tile ────────────────────────────────────────────────────────────

class _EmployeeScheduleTile extends ConsumerWidget {
  final EmployeeModel employee;
  const _EmployeeScheduleTile({required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProviderScope(
            parent: ProviderScope.containerOf(context),
            child: _ScheduleEditScreen(employee: employee),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  employee.fullName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  if (employee.teamName != null &&
                      employee.teamName!.isNotEmpty)
                    Text(
                      employee.teamName!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                        fontFamily: 'Inter',
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

// ─── Schedule Edit Screen ─────────────────────────────────────────────────────

class _ScheduleEditScreen extends ConsumerStatefulWidget {
  final EmployeeModel employee;
  const _ScheduleEditScreen({required this.employee});

  @override
  ConsumerState<_ScheduleEditScreen> createState() =>
      _ScheduleEditScreenState();
}

class _ScheduleEditScreenState
    extends ConsumerState<_ScheduleEditScreen> {
  static const _days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  // Map dayOfWeek → schedule state
  final Map<int, _DayState> _state = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Defaults
    for (int i = 0; i < 7; i++) {
      _state[i] = _DayState(
        isWorkday: i < 5,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 18, minute: 0),
      );
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final schedules = await ref
          .read(apiServiceProvider)
          .getEmployeeSchedules(widget.employee.id);
      for (final s in schedules) {
        TimeOfDay? start;
        TimeOfDay? end;
        if (s.startTime != null) {
          final parts = s.startTime!.split(':');
          start = TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (s.endTime != null) {
          final parts = s.endTime!.split(':');
          end = TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        _state[s.dayOfWeek] = _DayState(
          isWorkday: s.isWorkday,
          startTime: start ?? const TimeOfDay(hour: 9, minute: 0),
          endTime: end ?? const TimeOfDay(hour: 18, minute: 0),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    // Validate: working days must be >= 6 hours
    for (int i = 0; i < 7; i++) {
      final s = _state[i]!;
      if (s.isWorkday) {
        final startMin = s.startTime.hour * 60 + s.startTime.minute;
        final endMin = s.endTime.hour * 60 + s.endTime.minute;
        if (endMin - startMin < 360) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${_days[i]}: рабочий день должен быть не менее 6 часов'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      for (int i = 0; i < 7; i++) {
        final s = _state[i]!;
        await ref.read(apiServiceProvider).saveScheduleDay(
              userId: widget.employee.id,
              dayOfWeek: i,
              isWorkday: s.isWorkday,
              startTime: s.isWorkday
                  ? '${s.startTime.hour.toString().padLeft(2, '0')}:${s.startTime.minute.toString().padLeft(2, '0')}:00'
                  : null,
              endTime: s.isWorkday
                  ? '${s.endTime.hour.toString().padLeft(2, '0')}:${s.endTime.minute.toString().padLeft(2, '0')}:00'
                  : null,
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Расписание сохранено'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(int day, bool isStart) async {
    final s = _state[day]!;
    final initial = isStart ? s.startTime : s.endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null && mounted) {
      setState(() {
        _state[day] = isStart
            ? s.copyWith(startTime: picked)
            : s.copyWith(endTime: picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.employee.fullName),
        actions: [
          if (!_saving)
            TextButton(
              onPressed: _save,
              child: const Text(
                'Сохранить',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // Info banner
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: AppColors.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Минимальная продолжительность рабочего дня — 6 часов',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Days list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: 7,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) => _DayRow(
                      dayName: _days[i],
                      state: _state[i]!,
                      onToggle: (v) => setState(
                          () => _state[i] = _state[i]!.copyWith(isWorkday: v)),
                      onPickStart: () => _pickTime(i, true),
                      onPickEnd: () => _pickTime(i, false),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Day Row ──────────────────────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  final String dayName;
  final _DayState state;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _DayRow({
    required this.dayName,
    required this.state,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
  });

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: state.isWorkday ? AppColors.surface : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.isWorkday ? AppColors.border : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  dayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: state.isWorkday
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.isWorkday ? 'Рабочий день' : 'Выходной',
                  style: TextStyle(
                    fontSize: 14,
                    color: state.isWorkday
                        ? AppColors.success
                        : AppColors.textHint,
                    fontFamily: 'Inter',
                    fontWeight: state.isWorkday
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
              Switch(
                value: state.isWorkday,
                onChanged: onToggle,
                activeColor: AppColors.primary,
              ),
            ],
          ),
          if (state.isWorkday) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'Начало',
                    time: _fmt(state.startTime),
                    onTap: onPickStart,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('—',
                      style: TextStyle(color: AppColors.textHint)),
                ),
                Expanded(
                  child: _TimeButton(
                    label: 'Конец',
                    time: _fmt(state.endTime),
                    onTap: onPickEnd,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontFamily: 'Inter',
              ),
            ),
            Text(
              time,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── State model ──────────────────────────────────────────────────────────────

class _DayState {
  final bool isWorkday;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  const _DayState({
    required this.isWorkday,
    required this.startTime,
    required this.endTime,
  });

  _DayState copyWith({
    bool? isWorkday,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) =>
      _DayState(
        isWorkday: isWorkday ?? this.isWorkday,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/employee_schedule_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  List<EmployeeScheduleModel> _schedules = [];
  bool _loading = true;

  static const _dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _dayNamesFull = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final auth = ref.read(authProvider);
      final userId = auth.user?.id;
      if (userId == null) return;
      final schedules = await ApiService().getEmployeeSchedules(userId);
      if (mounted) setState(() => _schedules = schedules);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _todayDow {
    final w = DateTime.now().weekday; // 1=Mon … 7=Sun
    return w - 1; // 0=Mon … 6=Sun
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мой график'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    // Создаём карту dow → schedule
    final map = <int, EmployeeScheduleModel>{};
    for (final s in _schedules) {
      map[s.dayOfWeek] = s;
    }

    // Считаем суммарные рабочие часы
    int totalMinutes = 0;
    for (final s in _schedules) {
      if (s.isWorkingDay && s.startTime != null && s.endTime != null) {
        totalMinutes += s.durationMinutes;
      }
    }
    final totalHours = totalMinutes ~/ 60;
    final totalMins = totalMinutes % 60;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Сводная карточка
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Мой график',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalMins > 0
                          ? '$totalHours ч $totalMins мин / нед'
                          : '$totalHours ч / нед',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_schedules.where((s) => s.isWorkingDay).length} рабочих дней',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.calendar_month_rounded,
                  color: Colors.white54, size: 48),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Расписание по дням',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(7, (dow) {
          final schedule = map[dow];
          final isToday = dow == _todayDow;
          final isWorking = schedule?.isWorkingDay ?? false;

          return _DayCard(
            dayShort: _dayNames[dow],
            dayFull: _dayNamesFull[dow],
            isToday: isToday,
            isWorking: isWorking,
            startTime: schedule?.formattedStart,
            endTime: schedule?.formattedEnd,
            durationMinutes: schedule?.durationMinutes ?? 0,
          );
        }),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  final String dayShort;
  final String dayFull;
  final bool isToday;
  final bool isWorking;
  final String? startTime;
  final String? endTime;
  final int durationMinutes;

  const _DayCard({
    required this.dayShort,
    required this.dayFull,
    required this.isToday,
    required this.isWorking,
    this.startTime,
    this.endTime,
    required this.durationMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    final durationStr = durationMinutes > 0
        ? (mins > 0 ? '${hours}ч ${mins}м' : '$hours ч')
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday ? AppColors.primary : AppColors.border,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Кружок дня
            Container(
              width: 40,
              height: 40,
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
                  dayShort,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: isToday
                        ? Colors.white
                        : isWorking
                            ? AppColors.primary
                            : AppColors.textHint,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Название + статус
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        dayFull,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                          color: isWorking
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Сегодня',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (isWorking && startTime != null && endTime != null)
                    Text(
                      '$startTime – $endTime',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    )
                  else
                    const Text(
                      'Выходной',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                        fontFamily: 'Inter',
                      ),
                    ),
                ],
              ),
            ),
            // Длительность
            if (durationStr != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  durationStr,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

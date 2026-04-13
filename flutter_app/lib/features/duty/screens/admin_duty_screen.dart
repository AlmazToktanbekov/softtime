// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/duty_model.dart';
import '../../../core/models/user_model.dart';
import '../../../providers.dart';
import '../../../core/theme/app_theme.dart';

class AdminDutyScreen extends ConsumerStatefulWidget {
  const AdminDutyScreen({super.key});

  @override
  ConsumerState<AdminDutyScreen> createState() => _AdminDutyScreenState();
}

class _AdminDutyScreenState extends ConsumerState<AdminDutyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<DutyAssignment> _assignments = [];
  List<EmployeeModel> _employees = [];
  bool _loadingAssign = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadAssignments();
    _loadEmployees();
  }

  Future<void> _loadAssignments() async {
    setState(() => _loadingAssign = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final list = await ref.read(apiServiceProvider).getDutyScheduleAll(
            startDate: today,
          );
      if (mounted) setState(() => _assignments = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingAssign = false);
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await ref.read(apiServiceProvider).getEmployees();
      if (mounted) setState(() => _employees = list);
    } catch (_) {}
  }

  Future<void> _showAssignDialog() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет сотрудников'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    String? selectedId = _employees.first.id;
    DateTime selectedDate = DateTime.now();
    String selectedDutyType = 'LUNCH';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text(
            'Назначить дежурного',
            style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter'),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedId,
                decoration: const InputDecoration(labelText: 'Сотрудник'),
                items: _employees
                    .map((e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(e.fullName,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => selectedId = v),
              ),
              const SizedBox(height: 14),
              // Тип дежурства
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Тип дежурства',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                          fontFamily: 'Inter')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DutyTypeChip(
                        label: '🍽️  Обед',
                        selected: selectedDutyType == 'LUNCH',
                        onTap: () => setS(() => selectedDutyType = 'LUNCH'),
                      ),
                      const SizedBox(width: 10),
                      _DutyTypeChip(
                        label: '🧹  Уборка',
                        selected: selectedDutyType == 'CLEANING',
                        onTap: () => setS(() => selectedDutyType = 'CLEANING'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded,
                    color: AppColors.primary),
                title: const Text('Дата',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                        fontFamily: 'Inter')),
                subtitle: Text(
                  DateFormat('d MMMM yyyy', 'ru').format(selectedDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setS(() => selectedDate = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedId == null) return;
                try {
                  await ref.read(apiServiceProvider).assignDuty(
                        userId: selectedId!,
                        date: DateFormat('yyyy-MM-dd').format(selectedDate),
                        dutyType: selectedDutyType,
                      );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Назначить'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _loadAssignments();
  }

  Future<void> _verifyDuty(DutyAssignment a, bool approve) async {
    final noteCtrl = TextEditingController();
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отклонить дежурство?',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Причина отклонения (необязательно)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отклонить'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref.read(apiServiceProvider).verifyDuty(
            a.id,
            approve,
            adminNote: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(approve ? 'Дежурство подтверждено' : 'Дежурство отклонено'),
            backgroundColor:
                approve ? AppColors.success : AppColors.error,
          ),
        );
      }
      _loadAssignments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Filter: assignments needing verification
  List<DutyAssignment> get _pendingVerification => _assignments
      .where((a) => a.isCompleted && !a.verified)
      .toList();

  List<DutyAssignment> get _upcomingAssignments => _assignments
      .where((a) => !a.isCompleted)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  @override
  Widget build(BuildContext context) {
    final pendingCount = _pendingVerification.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Управление дежурствами'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: [
            const Tab(text: 'Расписание'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Проверка'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loadingAssign
          ? _buildShimmer()
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildScheduleTab(),
                _buildVerifyTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssignDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Назначить',
            style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      ),
    );
  }

  Widget _buildScheduleTab() {
    if (_upcomingAssignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.cleaning_services_rounded,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('Дежурств не запланир��вано',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter')),
            const SizedBox(height: 8),
            const Text('Нажмите «Назначить» для добавления',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                    fontFamily: 'Inter')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _upcomingAssignments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _AssignmentCard(assignment: _upcomingAssignments[i]),
      ),
    );
  }

  Widget _buildVerifyTab() {
    if (_pendingVerification.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: AppColors.successLight, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded,
                  size: 36, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            const Text('Нет ожидающих проверки',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingVerification.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _pendingVerification[i];
          return _VerifyCard(
            assignment: a,
            onApprove: () => _verifyDuty(a, true),
            onReject: () => _verifyDuty(a, false),
          );
        },
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─── Duty Type Chip ───────────────────────────────────────────────────────────

class _DutyTypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DutyTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

// ─── Assignment Card ──────────────────────────────────────────────────────────

class _AssignmentCard extends StatelessWidget {
  final DutyAssignment assignment;
  const _AssignmentCard({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(assignment.date) ?? DateTime.now();
    final dateStr = DateFormat('d MMMM yyyy', 'ru').format(date);
    final isToday = assignment.date ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isLunch = assignment.isLunch;
    final typeColor = isLunch ? AppColors.primary : const Color(0xFF34C759);
    final typeBg = isLunch ? AppColors.primaryLight : const Color(0xFFEAF7EC);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFEFF6FF) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday ? AppColors.primary : AppColors.border,
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isToday ? typeBg : AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                assignment.typeEmoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assignment.userFullName ?? 'Сотрудник',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isToday ? 'Сегодня — $dateStr' : dateStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: isToday ? AppColors.primary : AppColors.textSecondary,
                    fontFamily: 'Inter',
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  assignment.typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: typeColor,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              if (isToday) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Сегодня',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Verify Card ──────────────────────────────────────────────────────────────

class _VerifyCard extends StatelessWidget {
  final DutyAssignment assignment;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _VerifyCard({
    required this.assignment,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(assignment.date) ?? DateTime.now();
    final dateStr = DateFormat('d MMMM yyyy', 'ru').format(date);
    final tasksDone = (assignment.completionTasks?.length ?? 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pending_actions_rounded,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  assignment.userFullName ?? 'Сотрудник',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.task_alt_rounded,
                  size: 14, color: AppColors.success),
              const SizedBox(width: 5),
              Text(
                'Выполнено задач: $tasksDone',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(width: 12),
              if (assignment.completionQrVerified) ...[
                const Icon(Icons.qr_code_2_rounded,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 5),
                const Text(
                  'QR подтверждён',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.success,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Отклонить'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Подтвердить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

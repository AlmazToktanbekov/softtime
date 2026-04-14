// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/attendance_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../providers.dart';

class AdminAttendanceScreen extends ConsumerStatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  ConsumerState<AdminAttendanceScreen> createState() =>
      _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState
    extends ConsumerState<AdminAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  List<AttendanceModel> _records = [];
  List<EmployeeModel> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final results = await Future.wait([
        api.getAllAttendance(startDate: dateStr, endDate: dateStr),
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

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (d != null && d != _selectedDate) {
      setState(() => _selectedDate = d);
      _load();
    }
  }

  int get _present =>
      _records.where((r) => r.status == 'PRESENT' || r.status == 'LATE' || r.status == 'OVERTIME').length;
  int get _late => _records.where((r) => r.status == 'LATE').length;
  int get _inOffice =>
      _records.where((r) => r.checkInTime != null && r.checkOutTime == null).length;

  String _findName(String userId) {
    try {
      return _employees.firstWhere((e) => e.id == userId).fullName;
    } catch (_) {
      return userId.substring(0, 8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Посещаемость'),
        actions: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(
              isToday
                  ? 'Сегодня'
                  : DateFormat('d MMM', 'ru').format(_selectedDate),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildSummaryRow(),
                        const SizedBox(height: 16),
                        if (isToday && _inOffice > 0) ...[
                          _buildInOfficeSection(),
                          const SizedBox(height: 16),
                        ],
                        _buildAttendanceList(),
                        const SizedBox(height: 80),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'absence',
            onPressed: _showApprovedAbsenceDialog,
            backgroundColor: AppColors.purple,
            foregroundColor: Colors.white,
            child: const Icon(Icons.verified_user_rounded),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'manual',
            onPressed: _showManualCorrectionDialog,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Правка'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        _SummaryCard(
          value: '${_records.length}',
          label: 'Записей',
          color: AppColors.primary,
          bg: AppColors.primaryLight,
          icon: Icons.list_alt_rounded,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          value: '$_present',
          label: 'Пришли',
          color: AppColors.success,
          bg: AppColors.successLight,
          icon: Icons.check_circle_rounded,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          value: '$_late',
          label: 'Опоздали',
          color: AppColors.warning,
          bg: AppColors.warningLight,
          icon: Icons.timer_outlined,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          value: '$_inOffice',
          label: 'В офисе',
          color: AppColors.purple,
          bg: AppColors.purpleLight,
          icon: Icons.location_on_rounded,
        ),
      ],
    );
  }

  Widget _buildInOfficeSection() {
    final inOffice =
        _records.where((r) => r.checkInTime != null && r.checkOutTime == null).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Сейчас в офисе',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${inOffice.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: inOffice.map((r) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      _findName(r.userId),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      r.formattedCheckIn,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    if (_records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded, size: 48, color: AppColors.textHint),
              SizedBox(height: 12),
              Text(
                'Нет записей за выбранный день',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontFamily: 'Inter',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Записи',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(_records.length, (i) {
          final r = _records[i];
          return Container(
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
                      _findName(r.userId).substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
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
                        _findName(r.userId),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        '${r.formattedCheckIn} → ${r.formattedCheckOut}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: r.status),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showManualCorrectionForRecord(r),
                  child: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textHint),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showApprovedAbsenceDialog() async {
    if (_employees.isEmpty) return;
    String? selectedId = _employees.first.id;
    DateTime selectedDate = _selectedDate;
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Разрешённое отсутствие',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedId,
                  decoration: const InputDecoration(labelText: 'Сотрудник'),
                  items: _employees
                      .map((e) => DropdownMenuItem(
                          value: e.id, child: Text(e.fullName)))
                      .toList(),
                  onChanged: (v) => setS(() => selectedId = v),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Дата'),
                  subtitle: Text(
                      DateFormat('d MMMM yyyy', 'ru').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today_rounded,
                      color: AppColors.primary),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setS(() => selectedDate = d);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Причина *',
                    hintText: 'Больничный, отпуск…',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                if (noteCtrl.text.trim().isEmpty || selectedId == null) return;
                try {
                  await ref.read(apiServiceProvider).markApprovedAbsence(
                        userId: selectedId!,
                        date: DateFormat('yyyy-MM-dd').format(selectedDate),
                        note: noteCtrl.text.trim(),
                      );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: AppColors.error,
                    ));
                  }
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualCorrectionDialog() async {
    if (_employees.isEmpty) return;
    String? selectedId = _employees.first.id;
    final checkInCtrl = TextEditingController();
    final checkOutCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Ручная правка',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedId,
                  decoration: const InputDecoration(labelText: 'Сотрудник'),
                  items: _employees
                      .map((e) => DropdownMenuItem(
                          value: e.id, child: Text(e.fullName)))
                      .toList(),
                  onChanged: (v) => setS(() => selectedId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: checkInCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Время прихода (HH:MM)'),
                  keyboardType: TextInputType.datetime,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: checkOutCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Время ухода (HH:MM)'),
                  keyboardType: TextInputType.datetime,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Причина'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final dateStr =
                    DateFormat('yyyy-MM-dd').format(_selectedDate);
                final existing = _records
                    .where((r) => r.userId == selectedId)
                    .toList();

                try {
                  if (existing.isNotEmpty) {
                    final data = <String, dynamic>{'is_manual': true};
                    if (checkInCtrl.text.isNotEmpty) {
                      data['check_in_time'] =
                          '${dateStr}T${checkInCtrl.text}:00';
                    }
                    if (checkOutCtrl.text.isNotEmpty) {
                      data['check_out_time'] =
                          '${dateStr}T${checkOutCtrl.text}:00';
                    }
                    if (noteCtrl.text.isNotEmpty) {
                      data['note'] = noteCtrl.text.trim();
                    }
                    await ref
                        .read(apiServiceProvider)
                        .manualUpdate(existing.first.id, data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: AppColors.error,
                    ));
                  }
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualCorrectionForRecord(AttendanceModel record) async {
    final checkInCtrl = TextEditingController(text: record.formattedCheckIn);
    final checkOutCtrl = TextEditingController(text: record.formattedCheckOut);
    final noteCtrl = TextEditingController();
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Правка: ${_findName(record.userId)}',
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontFamily: 'Inter', fontSize: 15),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: checkInCtrl,
              decoration:
                  const InputDecoration(labelText: 'Время прихода (HH:MM)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: checkOutCtrl,
              decoration:
                  const InputDecoration(labelText: 'Время ухода (HH:MM)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Причина'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final data = <String, dynamic>{'is_manual': true};
              if (checkInCtrl.text.isNotEmpty) {
                data['check_in_time'] = '${dateStr}T${checkInCtrl.text}:00';
              }
              if (checkOutCtrl.text.isNotEmpty) {
                data['check_out_time'] = '${dateStr}T${checkOutCtrl.text}:00';
              }
              if (noteCtrl.text.isNotEmpty) {
                data['note'] = noteCtrl.text.trim();
              }
              try {
                await ref
                    .read(apiServiceProvider)
                    .manualUpdate(record.id, data);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Ошибка: $e'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;

  const _SummaryCard({
    required this.value,
    required this.label,
    required this.color,
    required this.bg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Inter',
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
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

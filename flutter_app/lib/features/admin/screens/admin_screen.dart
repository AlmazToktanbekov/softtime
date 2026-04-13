// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/attendance_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../providers.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<EmployeeModel> _employees = [];
  List<AttendanceModel> _attendance = [];
  Map<String, dynamic>? _dailyReport;
  bool _loadingEmps = true;
  bool _loadingAtt = true;
  bool _loadingReport = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _loadEmployees();
    _loadAttendance();
    _loadReport();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    if (mounted) setState(() => _loadingEmps = true);
    try {
      final emps = await ref.read(apiServiceProvider).getEmployees();
      if (!mounted) return;
      setState(() {
        _employees = emps;
        _loadingEmps = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEmps = false);
    }
  }

  Future<void> _loadAttendance() async {
    if (mounted) setState(() => _loadingAtt = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final records = await ref
          .read(apiServiceProvider)
          .getAllAttendance(startDate: today, endDate: today);
      if (!mounted) return;
      setState(() {
        _attendance = records;
        _loadingAtt = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAtt = false);
    }
  }

  Future<void> _loadReport() async {
    if (mounted) setState(() => _loadingReport = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final report = await ref.read(apiServiceProvider).getDailyReport(today);
      if (!mounted) return;
      setState(() {
        _dailyReport = report;
        _loadingReport = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  Future<void> _generateQR() async {
    try {
      await ref.read(apiServiceProvider).generateQR();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Новый QR-код сгенерирован'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showAddEmployeeDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Новый сотрудник',
          style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter'),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameCtrl, 'ФИО *'),
              const SizedBox(height: 12),
              _dialogField(emailCtrl, 'Email *'),
              const SizedBox(height: 12),
              _dialogField(phoneCtrl, 'Телефон'),
              const SizedBox(height: 12),
              _dialogField(deptCtrl, 'Команда / отдел'),
              const SizedBox(height: 12),
              _dialogField(userCtrl, 'Логин *'),
              const SizedBox(height: 12),
              _dialogField(passCtrl, 'Пароль *', obscure: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Валидация обязательных полей
              if (nameCtrl.text.trim().isEmpty ||
                  emailCtrl.text.trim().isEmpty ||
                  userCtrl.text.trim().isEmpty ||
                  passCtrl.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Заполните все обязательные поля (*)'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              final phone = phoneCtrl.text.trim();
              if (phone.isNotEmpty &&
                  !RegExp(r'^\+\d{10,15}$').hasMatch(phone)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Телефон в формате +996XXXXXXXXX'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              try {
                await ref.read(apiServiceProvider).createEmployee({
                  'full_name': nameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'phone': phone.isNotEmpty ? phone : null,
                  'team_name':
                      deptCtrl.text.isNotEmpty ? deptCtrl.text.trim() : null,
                  'username': userCtrl.text.trim(),
                  'password': passCtrl.text,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) _loadEmployees();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Ошибка: $e'),
                        backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label,
      {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
    );
  }

  Future<void> _showApprovedAbsenceDialog() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет сотрудников для выбора'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    String? selectedEmployeeId = _employees.first.id;
    DateTime selectedDate = DateTime.now();
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Разрешённое отсутствие',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter'),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Укажите, что сотруднику дано разрешение не прийти (с комментарием).',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedEmployeeId,
                    decoration: const InputDecoration(labelText: 'Сотрудник'),
                    items: _employees
                        .map((e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.fullName),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedEmployeeId = v),
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
                      if (d != null) {
                        setDialogState(() => selectedDate = d);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий (причина) *',
                      hintText: 'Больничный, отпуск, удалённая работа…',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final note = noteCtrl.text.trim();
                  if (note.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Укажите комментарий (причину)'),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                    return;
                  }
                  if (selectedEmployeeId == null) return;
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(apiServiceProvider).markApprovedAbsence(
                          userId: selectedEmployeeId!,
                          date: DateFormat('yyyy-MM-dd').format(selectedDate),
                          note: note,
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    _loadAttendance();
                    _loadReport();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Разрешённое отсутствие сохранено'),
                        backgroundColor: AppColors.success,
                      ),
                    );
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
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Панель администратора'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Сотрудники'),
            Tab(icon: Icon(Icons.checklist_outlined), text: 'Посещаемость'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Отчёт'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Управление'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            onPressed: _generateQR,
            tooltip: 'Сгенерировать QR',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _EmployeesTab(
            employees: _employees,
            loading: _loadingEmps,
            onRefresh: _loadEmployees,
          ),
          _AttendanceTab(
            records: _attendance,
            loading: _loadingAtt,
            onRefresh: _loadAttendance,
          ),
          _ReportTab(
            report: _dailyReport,
            loading: _loadingReport,
          ),
          const _ManageTab(),
        ],
      ),
      floatingActionButton: _tabCtrl.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddEmployeeDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Добавить'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : _tabCtrl.index == 1
              ? FloatingActionButton.extended(
                  onPressed: _showApprovedAbsenceDialog,
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('Разреш. отсутствие'),
                  backgroundColor: AppColors.purple,
                  foregroundColor: Colors.white,
                )
              : null,
    );
  }
}

// ─── Employees Tab ────────────────────────────────────────────────────────────

class _EmployeesTab extends StatelessWidget {
  final List<EmployeeModel> employees;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _EmployeesTab({
    required this.employees,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (employees.isEmpty) {
      return const Center(
        child: Text(
          'Сотрудников нет',
          style: TextStyle(
            color: AppColors.textHint,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: employees.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final emp = employees[i];
          return Container(
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
                      emp.fullName.substring(0, 1).toUpperCase(),
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
                        emp.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        emp.teamName?.isNotEmpty == true
                            ? emp.teamName!
                            : '—',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: emp.isActiveUser
                        ? AppColors.successLight
                        : AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    emp.isActiveUser ? 'Активен' : 'Неактивен',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                      color: emp.isActiveUser
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Attendance Tab ───────────────────────────────────────────────────────────

class _AttendanceTab extends StatelessWidget {
  final List<AttendanceModel> records;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _AttendanceTab({
    required this.records,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (records.isEmpty) {
      return const Center(
        child: Text(
          'Нет записей за сегодня',
          style: TextStyle(
            color: AppColors.textHint,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = records[i];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID: ${r.userId}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${r.formattedCheckIn} → ${r.formattedCheckOut}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: r.status),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Report Tab ───────────────────────────────────────────────────────────────

class _ReportTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final bool loading;

  const _ReportTab({required this.report, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (report == null) {
      return const Center(
        child: Text(
          'Нет данных',
          style: TextStyle(
            color: AppColors.textHint,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    final summary = report!['summary'] as Map<String, dynamic>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ежедневный отчёт',
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report!['date'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${summary['attendance_rate']}% посещаемость',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _StatCard(
                'Всего',
                '${summary['total_employees']}',
                Icons.people_outline,
                AppColors.primary,
                AppColors.primaryLight,
              ),
              _StatCard(
                'Присутствуют',
                '${summary['present']}',
                Icons.check_circle_outline,
                AppColors.success,
                AppColors.successLight,
              ),
              _StatCard(
                'Опоздали',
                '${summary['late']}',
                Icons.warning_amber_outlined,
                AppColors.warning,
                AppColors.warningLight,
              ),
              _StatCard(
                'Отсутствуют',
                '${summary['absent']}',
                Icons.cancel_outlined,
                AppColors.error,
                AppColors.errorLight,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatCard(this.label, this.value, this.icon, this.color, this.bgColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
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

// ─── Manage Tab ───────────────────────────────────────────────────────────────

class _ManageTab extends StatelessWidget {
  const _ManageTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 4),
        const Text(
          'Разделы управления',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textHint,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _ManageCard(
          icon: Icons.article_rounded,
          iconColor: AppColors.primary,
          iconBg: AppColors.primaryLight,
          title: 'Новости',
          subtitle: 'Создавать, редактировать и удалять новости',
          onTap: () => context.go('/home/admin/news'),
        ),
        const SizedBox(height: 10),
        _ManageCard(
          icon: Icons.assignment_ind_rounded,
          iconColor: AppColors.purple,
          iconBg: const Color(0xFFF3E8FF),
          title: 'Дежурство',
          subtitle: 'Назначать дежурных и подтверждать выполнение',
          onTap: () => context.go('/home/admin/duty'),
        ),
        const SizedBox(height: 10),
        _ManageCard(
          icon: Icons.calendar_month_rounded,
          iconColor: AppColors.success,
          iconBg: AppColors.successLight,
          title: 'Расписание',
          subtitle: 'Настраивать рабочий график каждого сотрудника',
          onTap: () => context.go('/home/admin/schedule'),
        ),
      ],
    );
  }
}

class _ManageCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManageCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

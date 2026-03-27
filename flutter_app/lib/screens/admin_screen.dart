import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import '../services/auth_provider.dart';

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
    _tabCtrl = TabController(length: 3, vsync: this);
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
    if (mounted) {
      setState(() => _loadingEmps = true);
    }

    try {
      final emps = await ref.read(apiServiceProvider).getEmployees();

      if (!mounted) return;

      setState(() {
        _employees = emps;
        _loadingEmps = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEmps = false);
    }
  }

  Future<void> _loadAttendance() async {
    if (mounted) {
      setState(() => _loadingAtt = true);
    }

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
      if (!mounted) return;
      setState(() => _loadingAtt = false);
    }
  }

  Future<void> _loadReport() async {
    if (mounted) {
      setState(() => _loadingReport = true);
    }

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final report = await ref.read(apiServiceProvider).getDailyReport(today);

      if (!mounted) return;

      setState(() {
        _dailyReport = report;
        _loadingReport = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReport = false);
    }
  }

  Future<void> _generateQR() async {
    try {
      await ref.read(apiServiceProvider).generateQR();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Новый QR-код сгенерирован'),
          backgroundColor: AppTheme.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _showAddEmployeeDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final posCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Новый сотрудник',
          style: TextStyle(fontWeight: FontWeight.w700),
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
              _dialogField(deptCtrl, 'Отдел'),
              const SizedBox(height: 12),
              _dialogField(posCtrl, 'Должность'),
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
              try {
                await ref.read(apiServiceProvider).createEmployee({
                  'full_name': nameCtrl.text,
                  'email': emailCtrl.text,
                  'phone': phoneCtrl.text.isNotEmpty ? phoneCtrl.text : null,
                  'department': deptCtrl.text.isNotEmpty ? deptCtrl.text : null,
                  'position': posCtrl.text.isNotEmpty ? posCtrl.text : null,
                  'username': userCtrl.text,
                  'password': passCtrl.text,
                });

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }

                if (mounted) {
                  _loadEmployees();
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: AppTheme.error,
                    ),
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
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    int? selectedEmployeeId = _employees.first.id;
    DateTime selectedDate = DateTime.now();
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Разрешённое отсутствие',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Укажите, что сотруднику дано разрешение не прийти (с комментарием).',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666688),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedEmployeeId,
                    decoration: const InputDecoration(
                      labelText: 'Сотрудник',
                    ),
                    items: _employees
                        .map((e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.fullName),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedEmployeeId = v),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дата'),
                    subtitle: Text(
                      DateFormat('d MMMM yyyy', 'ru').format(selectedDate),
                    ),
                    trailing: const Icon(Icons.calendar_today_rounded),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
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
                        backgroundColor: AppTheme.warning,
                      ),
                    );
                    return;
                  }
                  if (selectedEmployeeId == null) return;
                  try {
                    await ref.read(apiServiceProvider).markApprovedAbsence(
                          employeeId: selectedEmployeeId!,
                          date: DateFormat('yyyy-MM-dd').format(selectedDate),
                          note: note,
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      _loadAttendance();
                      _loadReport();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Разрешённое отсутствие сохранено'),
                          backgroundColor: AppTheme.accent,
                        ),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('Ошибка: $e'),
                          backgroundColor: AppTheme.error,
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
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Панель администратора'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: const Color(0xFF888899),
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Сотрудники'),
            Tab(icon: Icon(Icons.checklist_outlined), text: 'Посещаемость'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Отчёт'),
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
        ],
      ),
      floatingActionButton: _tabCtrl.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddEmployeeDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Добавить'),
              backgroundColor: AppTheme.primary,
            )
          : _tabCtrl.index == 1
              ? FloatingActionButton.extended(
                  onPressed: _showApprovedAbsenceDialog,
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('Разреш. отсутствие'),
                  backgroundColor: AppTheme.statusApprovedAbsence,
                )
              : null,
    );
  }
}

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
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: employees.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final emp = employees[i];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEEF5)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Text(
                    emp.fullName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
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
                        ),
                      ),
                      Text(
                        [emp.position, emp.department]
                            .where((s) => s != null)
                            .join(' • '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF888899),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: emp.isActive
                        ? AppTheme.accent.withOpacity(0.1)
                        : AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    emp.isActive ? 'Активен' : 'Неактивен',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: emp.isActive ? AppTheme.accent : AppTheme.error,
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
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = records[i];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEEF5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID: ${r.employeeId}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${r.formattedCheckIn} → ${r.formattedCheckOut}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666688),
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

class _ReportTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final bool loading;

  const _ReportTab({
    required this.report,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (report == null) {
      return const Center(child: Text('Нет данных'));
    }

    final summary = report!['summary'] as Map<String, dynamic>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Отчёт за ${report!['date']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                AppTheme.primary,
              ),
              _StatCard(
                'Присутствуют',
                '${summary['present']}',
                Icons.check_circle_outline,
                AppTheme.accent,
              ),
              _StatCard(
                'Опоздали',
                '${summary['late']}',
                Icons.warning_amber_outlined,
                AppTheme.warning,
              ),
              _StatCard(
                'Отсутствуют',
                '${summary['absent']}',
                Icons.cancel_outlined,
                AppTheme.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEEF5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Посещаемость',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                Text(
                  '${summary['attendance_rate']}%',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF888899)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
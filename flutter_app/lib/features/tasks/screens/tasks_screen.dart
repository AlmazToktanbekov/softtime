// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/task_model.dart';
import '../../../providers.dart';
import '../../../core/theme/app_theme.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen>
    with SingleTickerProviderStateMixin {
  List<Task> _tasks = [];
  bool _loading = true;
  late TabController _tabCtrl;

  static const _statuses = ['todo', 'in_progress', 'done', 'blocked'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      final tasks = await ref.read(apiServiceProvider).getTasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Task> _filtered(String status) =>
      _tasks.where((t) => t.status == status).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Задачи'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabAlignment: TabAlignment.start,
          tabs: [
            _buildTab('К выполнению', AppColors.textSecondary),
            _buildTab('В работе', AppColors.primary),
            _buildTab('Выполнено', AppColors.success),
            _buildTab('Заблокировано', AppColors.error),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : TabBarView(
              controller: _tabCtrl,
              children: _statuses
                  .map((s) => _TaskList(
                        tasks: _filtered(s),
                        status: s,
                        onStatusChange: _updateStatus,
                        onRefresh: _loadTasks,
                      ))
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Tab _buildTab(String label, Color color) {
    final count = _tasks.where((t) {
      final idx = _statuses.indexOf(
          _statuses.firstWhere((s) => _tabLabel(s) == label, orElse: () => ''));
      return idx >= 0 && t.status == _statuses[idx];
    }).length;

    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _tabLabel(String status) {
    switch (status) {
      case 'todo':
        return 'К выполнению';
      case 'in_progress':
        return 'В работе';
      case 'done':
        return 'Выполнено';
      case 'blocked':
        return 'Заблокировано';
      default:
        return status;
    }
  }

  Future<void> _updateStatus(String taskId, String newStatus) async {
    try {
      await ref.read(apiServiceProvider).updateTask(taskId, status: newStatus);
      _loadTasks();
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

  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final assigneeCtrl = TextEditingController();
    String priority = 'medium';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Новая задача',
            style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter'),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Название *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Описание (необязательно)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: assigneeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'ID исполнителя *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Приоритет'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Низкий')),
                    DropdownMenuItem(value: 'medium', child: Text('Средний')),
                    DropdownMenuItem(value: 'high', child: Text('Высокий')),
                    DropdownMenuItem(
                        value: 'critical', child: Text('Критический')),
                  ],
                  onChanged: (v) => setDialogState(() => priority = v!),
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
                if (titleCtrl.text.isEmpty || assigneeCtrl.text.isEmpty) return;
                try {
                  await ref.read(apiServiceProvider).createTask(
                        title: titleCtrl.text,
                        assigneeId: assigneeCtrl.text.trim(),
                        priority: priority,
                        description: descCtrl.text.isNotEmpty
                            ? descCtrl.text
                            : null,
                      );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _loadTasks();
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
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─── Task List ────────────────────────────────────────────────────────────────

class _TaskList extends StatelessWidget {
  final List<Task> tasks;
  final String status;
  final Future<void> Function(String, String) onStatusChange;
  final Future<void> Function() onRefresh;

  const _TaskList({
    required this.tasks,
    required this.status,
    required this.onStatusChange,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _statusConfig(status).$3,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _statusConfig(status).$2,
                size: 36,
                color: _statusConfig(status).$1,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Задач нет',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _TaskCard(
          task: tasks[i],
          onStatusChange: onStatusChange,
        ),
      ),
    );
  }

  (Color, IconData, Color) _statusConfig(String s) {
    switch (s) {
      case 'in_progress':
        return (AppColors.primary, Icons.play_circle_outline, AppColors.primaryLight);
      case 'done':
        return (AppColors.success, Icons.task_alt_rounded, AppColors.successLight);
      case 'blocked':
        return (AppColors.error, Icons.block_rounded, AppColors.errorLight);
      default:
        return (AppColors.textSecondary, Icons.inbox_outlined, AppColors.divider);
    }
  }
}

// ─── Task Card ────────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final Task task;
  final Future<void> Function(String, String) onStatusChange;

  const _TaskCard({required this.task, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final (color, _, bgColor) = _priorityConfig(task.priority);

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _priorityLabel(task.priority),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (v) => onStatusChange(task.id, v),
                icon: const Icon(Icons.more_horiz_rounded,
                    color: AppColors.textHint, size: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'todo', child: Text('К выполнению')),
                  PopupMenuItem(value: 'in_progress', child: Text('В работе')),
                  PopupMenuItem(value: 'done', child: Text('Выполнено')),
                  PopupMenuItem(value: 'blocked', child: Text('Заблокировано')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            task.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          if (task.description != null && task.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.description!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (task.dueDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 13, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  '${task.dueDate!.day.toString().padLeft(2, '0')}.${task.dueDate!.month.toString().padLeft(2, '0')}.${task.dueDate!.year}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (Color, IconData, Color) _priorityConfig(String p) {
    switch (p) {
      case 'critical':
        return (AppColors.error, Icons.priority_high, AppColors.errorLight);
      case 'high':
        return (AppColors.warning, Icons.arrow_upward, AppColors.warningLight);
      case 'low':
        return (AppColors.textSecondary, Icons.arrow_downward, AppColors.divider);
      default:
        return (AppColors.primary, Icons.remove, AppColors.primaryLight);
    }
  }

  String _priorityLabel(String p) {
    switch (p) {
      case 'critical':
        return 'Критический';
      case 'high':
        return 'Высокий';
      case 'low':
        return 'Низкий';
      default:
        return 'Средний';
    }
  }
}

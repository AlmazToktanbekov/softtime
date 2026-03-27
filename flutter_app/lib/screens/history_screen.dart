import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import '../services/auth_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<AttendanceModel> _records = [];
  bool _loading = true;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final start = _dateRange?.start;
      final end = _dateRange?.end;
      final records = await ref.read(apiServiceProvider).getMyAttendance(
        startDate: start != null ? DateFormat('yyyy-MM-dd').format(start) : null,
        endDate: end != null ? DateFormat('yyyy-MM-dd').format(end) : null,
      );
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      locale: const Locale('ru'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() => _dateRange = range);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('История посещений'),
        actions: [
          IconButton(
            icon: Icon(
              _dateRange != null ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _dateRange != null ? AppTheme.primary : const Color(0xFF888899),
            ),
            onPressed: _pickDateRange,
          ),
          if (_dateRange != null)
            IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF888899)),
              onPressed: () {
                setState(() => _dateRange = null);
                _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _records.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _AttendanceCard(record: _records[i]),
                  ),
                ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final AttendanceModel record;
  const _AttendanceCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(record.date);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEEEF5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('d MMMM', 'ru').format(date),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                  ),
                  Text(
                    DateFormat('EEEE', 'ru').format(date).capitalize(),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888899)),
                  ),
                ],
              ),
              const Spacer(),
              StatusBadge(status: record.status),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFF0F0F5), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              _InfoChip(icon: Icons.login_rounded, label: 'Приход', value: record.formattedCheckIn, color: AppTheme.accent),
              const SizedBox(width: 12),
              _InfoChip(icon: Icons.logout_rounded, label: 'Уход', value: record.formattedCheckOut, color: AppTheme.error),
              if (record.workDuration != null) ...[
                const SizedBox(width: 12),
                _InfoChip(icon: Icons.timer_outlined, label: 'Время', value: record.workDuration!, color: AppTheme.primary),
              ],
            ],
          ),
          if (record.lateMinutes > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Опоздание: ${record.lateMinutes} мин',
                  style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          if (record.note != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(record.note!, style: const TextStyle(fontSize: 12, color: Color(0xFF666688))),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Записей не найдено', style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Попробуйте изменить фильтр дат', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }
}

extension StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

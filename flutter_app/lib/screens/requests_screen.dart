import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/absence_request_model.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  TimeOfDay? _startTime;
  String _requestType = 'other';
  final TextEditingController _commentCtrl = TextEditingController();

  bool _submitting = false;
  bool _loadingMy = true;
  List<AbsenceRequestModel> _myRequests = [];

  static const List<Map<String, String>> _requestTypes = [
    {'id': 'sick', 'label': 'Больничный'},
    {'id': 'family', 'label': 'Семейные обстоятельства'},
    {'id': 'vacation', 'label': 'Отпуск'},
    {'id': 'business_trip', 'label': 'Командировка'},
    {'id': 'remote_work', 'label': 'Удалённая работа'},
    {'id': 'late_reason', 'label': 'Опоздание (по причине)'},
    {'id': 'early_leave', 'label': 'Ранний уход (по причине)'},
    {'id': 'other', 'label': 'Другое'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests() async {
    if (!mounted) return;
    setState(() => _loadingMy = true);
    try {
      final data = await ref.read(apiServiceProvider).getMyAbsenceRequests();
      if (!mounted) return;
      setState(() {
        _myRequests = data;
        _loadingMy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMy = false);
    }
  }

  bool get _needsTime =>
      _requestType == 'late_reason' || _requestType == 'early_leave';

  Future<void> _submitRequest() async {
    if (_commentCtrl.text.trim().isEmpty) {
      _showSnack('Добавьте комментарий', isError: true);
      return;
    }
    if (_needsTime && _startTime == null) {
      _showSnack('Для этого типа заявки укажите время', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final startDate = DateFormat('yyyy-MM-dd').format(_startDate);
      final endDate = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;
      final startTime = _startTime != null
          ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00'
          : null;

      await ref.read(apiServiceProvider).createAbsenceRequest(
            requestType: _requestType,
            startDate: startDate,
            endDate: endDate,
            startTime: startTime,
            commentEmployee: _commentCtrl.text.trim(),
          );

      if (!mounted) return;
      _commentCtrl.clear();
      _endDate = null;
      _startTime = null;
      _showSnack('Заявка отправлена');
      await _loadMyRequests();
      _tabController.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.accent,
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return 'Новая';
      case 'reviewing':
        return 'Рассматривается';
      case 'approved':
        return 'Одобрена';
      case 'rejected':
        return 'Отклонена';
      case 'needs_clarification':
        return 'Нужно уточнение';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'new':
        return AppTheme.primary;
      case 'reviewing':
        return AppTheme.warning;
      case 'approved':
        return AppTheme.accent;
      case 'rejected':
        return AppTheme.error;
      case 'needs_clarification':
        return AppTheme.statusApprovedAbsence;
      default:
        return const Color(0xFF888899);
    }
  }

  String _typeLabel(String id) {
    return _requestTypes.firstWhere(
      (t) => t['id'] == id,
      orElse: () => {'label': id},
    )['label']!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Заявки'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Новая заявка'),
            Tab(text: 'Мои заявки'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateTab(),
          _buildMyRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Тип заявки',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF666688)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _requestTypes.map((t) {
              final selected = _requestType == t['id'];
              return ChoiceChip(
                label: Text(t['label']!),
                selected: selected,
                onSelected: (_) => setState(() => _requestType = t['id']!),
                selectedColor: AppTheme.primary.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: selected ? AppTheme.primary : const Color(0xFF666688),
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _dateField(
            label: 'Дата начала',
            value: DateFormat('d MMMM yyyy', 'ru').format(_startDate),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _startDate = d);
            },
          ),
          const SizedBox(height: 12),
          _dateField(
            label: 'Дата окончания (необязательно)',
            value: _endDate == null
                ? 'Не выбрано'
                : DateFormat('d MMMM yyyy', 'ru').format(_endDate!),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _endDate ?? _startDate,
                firstDate: _startDate,
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _endDate = d);
            },
            onClear: _endDate == null ? null : () => setState(() => _endDate = null),
          ),
          const SizedBox(height: 12),
          if (_needsTime)
            _dateField(
              label: 'Время',
              value: _startTime == null
                  ? 'Не выбрано'
                  : '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}',
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _startTime ?? TimeOfDay.now(),
                );
                if (t != null) setState(() => _startTime = t);
              },
            ),
          if (_needsTime) const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Комментарий',
              hintText: 'Опишите причину...',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitRequest,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Отправка...' : 'Отправить заявку'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRequestsTab() {
    if (_loadingMy) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_myRequests.isEmpty) {
      return const Center(
        child: Text(
          'У вас пока нет заявок',
          style: TextStyle(color: Color(0xFF888899), fontWeight: FontWeight.w600),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMyRequests,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _myRequests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _myRequests[i];
          final statusColor = _statusColor(r.status);
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEEEF5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _typeLabel(r.requestType),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(r.status),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Период: ${r.startDate}${r.endDate != null ? ' - ${r.endDate}' : ''}',
                  style: const TextStyle(color: Color(0xFF666688), fontSize: 13),
                ),
                if (r.commentEmployee != null && r.commentEmployee!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Вы: ${r.commentEmployee}',
                    style: const TextStyle(color: Color(0xFF333355), fontSize: 13),
                  ),
                ],
                if (r.commentAdmin != null && r.commentAdmin!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Админ: ${r.commentAdmin}',
                    style: const TextStyle(color: Color(0xFF0D47A1), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
              )
            else
              const Icon(Icons.calendar_today_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}


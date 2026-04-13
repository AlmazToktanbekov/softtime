// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/absence_request_model.dart';
import '../../../providers.dart';
import '../../../core/theme/app_theme.dart';

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
      final endDate =
          _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;
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
      setState(() {
        _endDate = null;
        _startTime = null;
      });
      _showSnack('Заявка успешно отправлена');
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
        backgroundColor: isError ? AppColors.error : AppColors.success,
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
        return AppColors.primary;
      case 'reviewing':
        return AppColors.warning;
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'needs_clarification':
        return AppColors.purple;
      default:
        return AppColors.textHint;
    }
  }

  String _typeLabel(String id) {
    return _requestTypes
        .firstWhere(
          (t) => t['id'] == id,
          orElse: () => {'label': id},
        )['label']!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Тип заявки',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _requestTypes.map((t) {
              final selected = _requestType == t['id'];
              return GestureDetector(
                onTap: () => setState(() => _requestType = t['id']!),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryLight : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    t['label']!,
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
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
          if (_needsTime) ...[
            const SizedBox(height: 12),
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
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Комментарий',
              hintText: 'Опишите причину...',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitRequest,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label:
                  Text(_submitting ? 'Отправка...' : 'Отправить заявку'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRequestsTab() {
    if (_loadingMy) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_myRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_outlined,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'У вас пока нет заявок',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Отправьте заявку на первой вкладке',
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMyRequests,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _myRequests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _myRequests[i];
          final color = _statusColor(r.status);
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
                    Expanded(
                      child: Text(
                        _typeLabel(r.requestType),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(r.status),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 13, color: AppColors.textHint),
                    const SizedBox(width: 5),
                    Text(
                      r.endDate != null
                          ? '${r.startDate} — ${r.endDate}'
                          : r.startDate,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
                if (r.commentEmployee != null &&
                    r.commentEmployee!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ваш комментарий: ${r.commentEmployee}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                if (r.commentAdmin != null && r.commentAdmin!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r.commentAdmin!,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
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
                      color: AppColors.textHint,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textHint),
              )
            else
              const Icon(Icons.calendar_today_rounded,
                  size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

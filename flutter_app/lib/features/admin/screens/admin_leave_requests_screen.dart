import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/absence_request_model.dart';
import '../../../core/models/user_model.dart';
import '../../../providers.dart';

class AdminLeaveRequestsScreen extends ConsumerStatefulWidget {
  const AdminLeaveRequestsScreen({super.key});

  @override
  ConsumerState<AdminLeaveRequestsScreen> createState() =>
      _AdminLeaveRequestsScreenState();
}

class _AdminLeaveRequestsScreenState
    extends ConsumerState<AdminLeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<AbsenceRequestModel> _requests = [];
  List<EmployeeModel> _employees = [];
  bool _loading = true;

  String _employeeName(String userId) {
    try {
      return _employees.firstWhere((e) => e.id == userId).fullName;
    } catch (_) {
      return userId.length > 8 ? userId.substring(0, 8) : userId;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ref.read(apiServiceProvider).getAbsenceRequests(),
        ref.read(apiServiceProvider).getEmployees(),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0] as List<AbsenceRequestModel>;
        _employees = results[1] as List<EmployeeModel>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AbsenceRequestModel> get _filtered {
    switch (_tabCtrl.index) {
      case 1:
        return _requests.where((r) => r.status == 'PENDING').toList();
      case 2:
        return _requests.where((r) => r.status == 'APPROVED').toList();
      default:
        return List.from(_requests);
    }
  }

  int get _pendingCount =>
      _requests.where((r) => r.status == 'PENDING').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Заявки на отпуск'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            const Tab(text: 'Все'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ожидают'),
                  if (_pendingCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_pendingCount',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Одобрено'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Заявок нет',
                        style: TextStyle(
                            color: AppColors.textHint, fontFamily: 'Inter'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final req = _filtered[i];
                        return _RequestCard(
                          request: req,
                          employeeName: _employeeName(req.userId),
                          onApprove: req.status == 'PENDING'
                              ? () => _review(req.id, 'APPROVED')
                              : null,
                          onReject: req.status == 'PENDING'
                              ? () => _showRejectDialog(req.id)
                              : null,
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> _review(String id, String status, {String? comment}) async {
    try {
      await ref.read(apiServiceProvider).reviewAbsenceRequest(
            requestId: id,
            status: status,
            commentAdmin: comment,
          );
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'APPROVED' ? 'Заявка одобрена' : 'Заявка отклонена'),
          backgroundColor:
              status == 'APPROVED' ? AppColors.success : AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _showRejectDialog(String id) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отклонить заявку',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Комментарий (опционально)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              _review(id, 'REJECTED',
                  comment: ctrl.text.isNotEmpty ? ctrl.text : null);
            },
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
  }
}

// ─── Request Card ─────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final AbsenceRequestModel request;
  final String employeeName;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _RequestCard({
    required this.request,
    required this.employeeName,
    this.onApprove,
    this.onReject,
  });

  Color get _statusColor {
    switch (request.status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  Color get _statusBg {
    switch (request.status) {
      case 'APPROVED':
        return AppColors.successLight;
      case 'REJECTED':
        return AppColors.errorLight;
      default:
        return AppColors.warningLight;
    }
  }

  String get _statusLabel {
    switch (request.status) {
      case 'APPROVED':
        return 'Одобрено';
      case 'REJECTED':
        return 'Отклонено';
      default:
        return 'Ожидает';
    }
  }

  String get _typeLabel {
    switch (request.requestType) {
      case 'VACATION':
        return 'Отпуск';
      case 'SICK_LEAVE':
        return 'Больничный';
      case 'PERSONAL':
        return 'Личные причины';
      case 'REMOTE_WORK':
        return 'Удалённая работа';
      default:
        return request.requestType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM', 'ru');
    final dateRange = request.endDate != null && request.endDate != request.startDate
        ? '${fmt.format(DateTime.parse(request.startDate))} — ${fmt.format(DateTime.parse(request.endDate!))}'
        : fmt.format(DateTime.parse(request.startDate));

    return Container(
      padding: const EdgeInsets.all(14),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employeeName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _typeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateRange,
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
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          if (request.commentEmployee?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              request.commentEmployee!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onReject,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close_rounded,
                              color: AppColors.error, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Отклонить',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onApprove,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded,
                              color: AppColors.success, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Одобрить',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
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

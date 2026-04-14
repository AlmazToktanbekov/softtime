// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/duty_model.dart';
import '../../../core/models/user_model.dart';
import '../../../providers.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class DutyScreen extends ConsumerStatefulWidget {
  const DutyScreen({super.key});

  @override
  ConsumerState<DutyScreen> createState() => _DutyScreenState();
}

class _DutyScreenState extends ConsumerState<DutyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  List<DutyAssignment> _todayDuties = [];
  List<DutyAssignment> _upcoming = [];
  List<DutyChecklistItem> _checklist = [];
  List<DutySwap> _incomingSwaps = [];

  // checklist checkbox state per assignment id
  final Map<String, Map<String, bool>> _checked = {};

  bool _loadingToday = true;
  bool _loadingSchedule = true;
  bool _loadingChecklist = true;
  bool _loadingSwaps = true;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadToday();
    _loadSchedule();
    _loadChecklist();
    _loadSwaps();
  }

  Future<void> _loadToday() async {
    setState(() => _loadingToday = true);
    try {
      final duties = await ref.read(apiServiceProvider).getTodayDuties();
      if (mounted) setState(() => _todayDuties = duties);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingToday = false);
    }
  }

  Future<void> _loadSchedule() async {
    setState(() => _loadingSchedule = true);
    try {
      final list = await ref.read(apiServiceProvider).getMyDutyAssignments();
      if (mounted) setState(() => _upcoming = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSchedule = false);
    }
  }

  Future<void> _loadChecklist() async {
    setState(() => _loadingChecklist = true);
    try {
      final items = await ref.read(apiServiceProvider).getDutyChecklist();
      if (mounted) {
        setState(() {
          _checklist = items;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingChecklist = false);
    }
  }

  Future<void> _loadSwaps() async {
    setState(() => _loadingSwaps = true);
    try {
      final swaps = await ref.read(apiServiceProvider).getIncomingSwaps();
      if (mounted) setState(() => _incomingSwaps = swaps);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSwaps = false);
    }
  }

  List<DutyChecklistItem> _itemsForDuty(DutyAssignment duty) {
    return _checklist
        .where((i) => i.dutyType == null || i.dutyType == duty.dutyType)
        .toList();
  }

  Map<String, bool> _checklistMapFor(DutyAssignment duty) {
    final items = _itemsForDuty(duty);
    final id = duty.id;
    _checked.putIfAbsent(id, () => {});
    final map = _checked[id]!;
    for (final i in items) {
      map.putIfAbsent(i.id, () => false);
    }
    map.removeWhere((key, _) => !items.any((i) => i.id == key));
    return map;
  }

  bool _allCheckedFor(DutyAssignment duty) {
    final items = _itemsForDuty(duty);
    if (items.isEmpty) return true;
    final map = _checklistMapFor(duty);
    return items.every((i) => map[i.id] == true);
  }

  Future<void> _completeDuty(DutyAssignment assignment) async {
    final qrToken = await context.push<String>('/qr-scanner', extra: 'duty_complete');
    if (qrToken == null || !mounted) return;

    setState(() => _completing = true);
    try {
      final taskIds = _checklistMapFor(assignment)
          .entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      await ref.read(apiServiceProvider).completeDuty(
            assignmentId: assignment.id,
            taskIds: taskIds,
            qrToken: qrToken,
          );
      if (!mounted) return;
      _showSnack('Дежурство отправлено на проверку!', AppColors.success);
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      final msg = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(e.toString())?.group(1)
          ?? 'Ошибка при подтверждении';
      _showSnack(msg, AppColors.error);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _showSwapDialog(DutyAssignment assignment) async {
    List<EmployeeModel> employees = [];
    String? selectedId;
    bool loadingEmployees = true;
    List<DutyAssignment> peerSlots = [];
    bool loadingPeer = false;
    String? selectedPeerAssignmentId; // null = коллега просто берёт ваше дежурство

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (loadingEmployees) {
            ref.read(apiServiceProvider).getEmployees().then((list) {
              final me = ref.read(authProvider).user?.id;
              final filtered = list.where((e) => e.id != me).toList();
              setLocal(() {
                employees = filtered;
                loadingEmployees = false;
              });
            }).catchError((_) {
              setLocal(() => loadingEmployees = false);
            });
          }

          Future<void> loadPeer(String userId) async {
            setLocal(() {
              loadingPeer = true;
              peerSlots = [];
              selectedPeerAssignmentId = null;
            });
            try {
              final list =
                  await ref.read(apiServiceProvider).getPeerDutyAssignments(userId);
              final sameType =
                  list.where((a) => a.dutyType == assignment.dutyType && !a.isCompleted).toList();
              setLocal(() {
                peerSlots = sameType;
                loadingPeer = false;
              });
            } catch (_) {
              setLocal(() => loadingPeer = false);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Запрос обмена',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 4),
                _DutyTypeBadge(dutyType: assignment.dutyType),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ваше дежурство: ${_formatDate(assignment.date)}. '
                      'Второй сотрудник подтверждает обмен без админа. '
                      'После обмена отметка выполнения — через QR и подтверждение админа.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter',
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (loadingEmployees)
                      const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    else if (employees.isEmpty)
                      const Text('Нет доступных сотрудников',
                          style: TextStyle(color: AppColors.textHint, fontFamily: 'Inter'))
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedId,
                            isExpanded: true,
                            hint: const Text('Выберите сотрудника',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 14)),
                            items: employees
                                .map((e) => DropdownMenuItem(
                                      value: e.id,
                                      child: Row(children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: AppColors.primaryLight,
                                          child: Text(e.fullName[0],
                                              style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                            child: Text(e.fullName,
                                                style: const TextStyle(
                                                    fontFamily: 'Inter', fontSize: 14))),
                                      ]),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setLocal(() => selectedId = val);
                              if (val != null) loadPeer(val);
                            },
                          ),
                        ),
                      ),
                    if (selectedId != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Тип обмена',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            fontFamily: 'Inter'),
                      ),
                      const SizedBox(height: 8),
                      if (loadingPeer)
                        const Center(
                            child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        ))
                      else if (peerSlots.isEmpty)
                        const Text(
                          'У коллеги нет будущих дежурств этого типа — он просто возьмёт ваше назначение.',
                          style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Inter'),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: selectedPeerAssignmentId,
                              isExpanded: true,
                              hint: const Text('Только моё → коллеге',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 13)),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Передать только моё дежурство',
                                      style: TextStyle(fontFamily: 'Inter', fontSize: 13)),
                                ),
                                ...peerSlots.map((a) => DropdownMenuItem<String?>(
                                      value: a.id,
                                      child: Text(
                                        'Взаимно: их дата ${_formatDate(a.date)}',
                                        style: const TextStyle(
                                            fontFamily: 'Inter', fontSize: 13),
                                      ),
                                    )),
                              ],
                              onChanged: (v) => setLocal(() => selectedPeerAssignmentId = v),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена', style: TextStyle(color: AppColors.textHint)),
              ),
              ElevatedButton(
                onPressed: selectedId == null
                    ? null
                    : () => Navigator.of(ctx).pop({
                          'userId': selectedId,
                          'peerAssignmentId': selectedPeerAssignmentId,
                        }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(0, 40),
                ),
                child: const Text('Отправить', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;
    final targetId = result['userId'];
    if (targetId == null || targetId.isEmpty) return;
    try {
      await ref.read(apiServiceProvider).requestSwap(
        assignmentId: assignment.id,
        targetUserId: targetId,
        targetAssignmentId: result['peerAssignmentId'],
      );
      if (!mounted) return;
      _showSnack('Запрос на обмен отправлен!', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      final msg = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(e.toString())?.group(1) ??
          'Ошибка при отправке запроса';
      _showSnack(msg, AppColors.error);
    }
  }

  Future<void> _acceptSwap(String swapId) async {
    try {
      final msg = await ref.read(apiServiceProvider).acceptSwap(swapId);
      if (!mounted) return;
      _showSnack(msg ?? 'Обмен принят!', AppColors.success);
      _loadSwaps();
      _loadSchedule();
      _loadToday();
    } catch (_) {
      _showSnack('Ошибка при принятии обмена', AppColors.error);
    }
  }

  Future<void> _rejectSwap(String swapId) async {
    try {
      await ref.read(apiServiceProvider).rejectSwap(swapId);
      _showSnack('Обмен отклонён', AppColors.textSecondary);
      _loadSwaps();
    } catch (_) {
      _showSnack('Ошибка', AppColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      backgroundColor: color,
    ));
  }

  String _formatDate(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    return DateFormat('d MMMM, EEEE', 'ru').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user?.id;
    final myTodayDuties = _todayDuties.where((d) => d.userId == me).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Дежурство'),
        actions: [
          if (_incomingSwaps.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: () => _tab.animateTo(1),
                  tooltip: 'Запросы обмена',
                ),
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${_incomingSwaps.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            const Tab(text: 'Дежурство'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Обмены'),
                  if (_incomingSwaps.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_incomingSwaps.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── Tab 1: My duty ──────────────────────────────────────────────────
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadAll,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Today's duty cards (all employees + who is duty person)
                _TodaySection(
                  duties: _todayDuties,
                  loading: _loadingToday,
                  myUserId: me,
                ),
                const SizedBox(height: 20),

                // My checklists for today's duties
                               ...myTodayDuties.map((duty) => Column(
                  children: [
                    _ChecklistCard(
                      assignment: duty,
                      items: _itemsForDuty(duty),
                      loading: _loadingChecklist,
                      checked: _checklistMapFor(duty),
                      onToggle: (id, val) => setState(() {
                        _checklistMapFor(duty)[id] = val;
                      }),
                      allChecked: _allCheckedFor(duty),
                      completing: _completing,
                      onComplete: () => _completeDuty(duty),
                    ),
                    const SizedBox(height: 16),
                  ],
                )),

                // Upcoming duties
                _UpcomingCard(
                  assignments: _upcoming,
                  loading: _loadingSchedule,
                  onSwapRequest: _showSwapDialog,
                ),
              ],
            ),
          ),

          // ── Tab 2: Swaps ────────────────────────────────────────────────────
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadSwaps,
            child: _loadingSwaps
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _incomingSwaps.isEmpty
                    ? const _EmptyState(
                        icon: Icons.swap_horiz_rounded,
                        text: 'Нет входящих запросов на обмен',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _incomingSwaps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _SwapCard(
                          swap: _incomingSwaps[i],
                          onAccept: () => _acceptSwap(_incomingSwaps[i].id),
                          onReject: () => _rejectSwap(_incomingSwaps[i].id),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Today Section ─────────────────────────────────────────────────────────────

class _TodaySection extends StatelessWidget {
  final List<DutyAssignment> duties;
  final bool loading;
  final String? myUserId;

  const _TodaySection({
    required this.duties,
    required this.loading,
    required this.myUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }

    if (duties.isEmpty) {
      return const _DutyCard(
        icon: Icons.event_available_rounded,
        title: 'Дежурства сегодня нет',
        subtitle: null,
        gradient: LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF475569)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shadowColor: Color(0xFF64748B),
        statusLabel: null,
        statusColor: null,
      );
    }

    return Column(
      children: duties.map((duty) {
        final isMe = duty.userId == myUserId;
        final isLunch = duty.isLunch;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _DutyCard(
            icon: isLunch ? Icons.restaurant_rounded : Icons.cleaning_services_rounded,
            title: isMe
                ? 'Вы сегодня дежурите! (${duty.typeLabel})'
                : '${duty.userFullName ?? 'Сотрудник'} — ${duty.typeLabel}',
            subtitle: isMe
                ? isLunch
                    ? 'Приготовьте обед: от доставки еды до мытья посуды и порядка. '
 'Не можете — отправьте обмен коллеге; после принятия он дежурит. '
                        'Затем QR в офисе и подтверждение админа.'
                    : 'Уборка в удобный день недели: отметьте чеклист и отсканируйте QR в офисе.'
                : null,
            gradient: isMe
                ? const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: isLunch
                        ? [AppColors.primary, AppColors.primaryDark]
                        : [const Color(0xFF7C3AED), const Color(0xFF5B21B6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            shadowColor: isMe
                ? AppColors.warning
                : isLunch
                    ? AppColors.primary
                    : const Color(0xFF7C3AED),
            statusLabel: duty.verified
                ? 'Подтверждено'
                : duty.isCompleted
                    ? 'Ожидает проверки'
                    : 'Не выполнено',
            statusColor: duty.verified
                ? AppColors.success
                : duty.isCompleted
                    ? AppColors.warning
                    : Colors.white54,
          ),
        );
      }).toList(),
    );
  }
}

class _DutyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final LinearGradient gradient;
  final Color shadowColor;
  final String? statusLabel;
  final Color? statusColor;

  const _DutyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.shadowColor,
    required this.statusLabel,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.3),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, fontFamily: 'Inter', height: 1.3)),
                ],
                if (statusLabel != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusLabel!,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Checklist Card ────────────────────────────────────────────────────────────

class _ChecklistCard extends StatelessWidget {
  final DutyAssignment assignment;
  final List<DutyChecklistItem> items;
  final bool loading;
  final Map<String, bool> checked;
  final void Function(String id, bool val) onToggle;
  final bool allChecked;
  final bool completing;
  final VoidCallback onComplete;

  const _ChecklistCard({
    required this.assignment,
    required this.items,
    required this.loading,
    required this.checked,
    required this.onToggle,
    required this.allChecked,
    required this.completing,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final done = checked.values.where((v) => v).length;
    final total = items.length;
    final progress = total == 0 ? 0.0 : done / total;
    final isLunch = assignment.isLunch;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLunch ? const Color(0xFFFEF3C7) : const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(assignment.typeEmoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Задачи — ${assignment.typeLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isLunch ? const Color(0xFFD97706) : const Color(0xFF7C3AED),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$done / $total',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.primary, fontFamily: 'Inter')),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              color: progress == 1.0 ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),

          if (loading)
            _shimmerList()
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Нет задач для этого дежурства',
                  style: TextStyle(color: AppColors.textHint, fontFamily: 'Inter', fontSize: 13)),
            )
          else
            ...items.map((item) {
              final isChecked = checked[item.id] ?? false;
              return _CheckItem(
                text: item.text,
                checked: isChecked,
                onTap: () => onToggle(item.id, !isChecked),
              );
            }),

          const SizedBox(height: 16),

          if (!assignment.isCompleted)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: allChecked && !completing ? onComplete : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  disabledBackgroundColor: AppColors.divider,
                  disabledForegroundColor: AppColors.textHint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: completing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.qr_code_scanner_rounded, size: 20),
                label: Text(
                  completing ? 'Отправка...' : 'Подтвердить (скан QR)',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: assignment.verified ? AppColors.successLight : AppColors.warningLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    assignment.verified ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                    color: assignment.verified ? AppColors.success : AppColors.warning,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    assignment.verified ? 'Дежурство подтверждено' : 'Ожидает проверки администратора',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: assignment.verified ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),

          if (!allChecked && items.isNotEmpty && !assignment.isCompleted) ...[
            const SizedBox(height: 8),
            const Center(
              child: Text('Отметьте все задачи, чтобы открыть сканирование QR',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Inter')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shimmerList() => Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Column(
          children: List.generate(3, (_) => Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          )),
        ),
      );
}

class _CheckItem extends StatelessWidget {
  final String text;
  final bool checked;
  final VoidCallback onTap;

  const _CheckItem({required this.text, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: checked ? AppColors.successLight : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: checked ? AppColors.success : AppColors.border),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: checked ? AppColors.success : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: checked ? AppColors.success : AppColors.border, width: 1.5,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Inter',
                  color: checked ? AppColors.textSecondary : AppColors.textPrimary,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upcoming Card ─────────────────────────────────────────────────────────────

class _UpcomingCard extends StatelessWidget {
  final List<DutyAssignment> assignments;
  final bool loading;
  final void Function(DutyAssignment)? onSwapRequest;

  const _UpcomingCard({
    required this.assignments,
    required this.loading,
    this.onSwapRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Мои ближайшие дежурства',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary, fontFamily: 'Inter')),
          const SizedBox(height: 14),
          if (loading)
            Shimmer.fromColors(
              baseColor: const Color(0xFFEEEEEE),
              highlightColor: const Color(0xFFFAFAFA),
              child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(10))),
            )
          else if (assignments.isEmpty)
            const _EmptyState(icon: Icons.event_available_rounded, text: 'Нет ближайших дежурств')
          else
            ...assignments.map((a) => _AssignmentTile(
                  assignment: a,
                  onSwapRequest: onSwapRequest != null ? () => onSwapRequest!(a) : null,
                )),
        ],
      ),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  final DutyAssignment assignment;
  final VoidCallback? onSwapRequest;

  const _AssignmentTile({required this.assignment, this.onSwapRequest});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(assignment.date);
    final dateStr = date != null
        ? DateFormat('d MMMM, EEEE', 'ru').format(date)
        : assignment.date;

    Color statusColor;
    String statusLabel;
    if (assignment.verified) {
      statusColor = AppColors.success;
      statusLabel = 'Подтверждено';
    } else if (assignment.isCompleted) {
      statusColor = AppColors.warning;
      statusLabel = 'На проверке';
    } else {
      statusColor = AppColors.primary;
      statusLabel = 'Предстоит';
    }

    final isLunch = assignment.isLunch;
    final typeColor = isLunch ? const Color(0xFFD97706) : const Color(0xFF7C3AED);
    final typeBg = isLunch ? const Color(0xFFFEF3C7) : const Color(0xFFEDE9FE);
    final typeIcon = isLunch ? Icons.restaurant_rounded : Icons.cleaning_services_rounded;
    final isPending = !assignment.isCompleted && !assignment.verified;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(typeIcon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateStr,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary, fontFamily: 'Inter')),
                    const SizedBox(height: 2),
                    Text(assignment.typeLabel,
                        style: TextStyle(fontSize: 12, color: typeColor, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: statusColor, fontFamily: 'Inter')),
              ),
            ],
          ),
          if (isPending && onSwapRequest != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: onSwapRequest,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Запросить обмен',
                    style: TextStyle(fontSize: 12, fontFamily: 'Inter')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Swap Card ─────────────────────────────────────────────────────────────────

class _SwapCard extends StatelessWidget {
  final DutySwap swap;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _SwapCard({required this.swap, required this.onAccept, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(swap.createdAt);
    final createdStr = created != null ? DateFormat('d MMM, HH:mm', 'ru').format(created.toLocal()) : '';
    final dutyDate = swap.dutyDate != null ? DateTime.tryParse(swap.dutyDate!) : null;
    final dutyDateStr = dutyDate != null ? DateFormat('d MMMM', 'ru').format(dutyDate) : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 14, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text('${swap.dutyTypeLabel}${dutyDateStr.isNotEmpty ? ' · $dutyDateStr' : ''}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: AppColors.warning, fontFamily: 'Inter')),
                  ],
                ),
              ),
              const Spacer(),
              Text(createdStr,
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Inter')),
            ],
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontFamily: 'Inter', height: 1.4),
              children: [
                TextSpan(
                  text: swap.requesterName ?? 'Сотрудник',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' хочет передать вам своё дежурство'),
                if (dutyDateStr.isNotEmpty)
                  TextSpan(text: ' ($dutyDateStr)'),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          if (swap.targetPeerDate != null && swap.targetPeerDate!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Взаимный обмен: вы отдаёте своё дежурство на ${_formatSwapPeerDate(swap.targetPeerDate!)}.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Отклонить',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Принять',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

class _DutyTypeBadge extends StatelessWidget {
  final String dutyType;
  const _DutyTypeBadge({required this.dutyType});

  @override
  Widget build(BuildContext context) {
    final isLunch = dutyType == 'LUNCH';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isLunch ? const Color(0xFFFEF3C7) : const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLunch ? '🍽️ Обед' : '🧹 Уборка',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isLunch ? const Color(0xFFD97706) : const Color(0xFF7C3AED),
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

String _formatSwapPeerDate(String raw) {
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  return DateFormat('d MMMM', 'ru').format(dt);
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(text,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 14, fontFamily: 'Inter'),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

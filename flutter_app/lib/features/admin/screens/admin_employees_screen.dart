// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/user_model.dart';
import '../../../providers.dart';

class AdminEmployeesScreen extends ConsumerStatefulWidget {
  const AdminEmployeesScreen({super.key});

  @override
  ConsumerState<AdminEmployeesScreen> createState() =>
      _AdminEmployeesScreenState();
}

class _AdminEmployeesScreenState extends ConsumerState<AdminEmployeesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<EmployeeModel> _all = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final emps = await ref.read(apiServiceProvider).getEmployees();
      if (!mounted) return;
      setState(() {
        _all = emps
            .where((e) => !['ADMIN', 'SUPER_ADMIN'].contains(e.role))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<EmployeeModel> get _filtered {
    List<EmployeeModel> list;
    switch (_tabCtrl.index) {
      case 1:
        list = _all.where((e) => e.status == 'PENDING').toList();
        break;
      case 2:
        list = _all.where((e) => e.status == 'ACTIVE').toList();
        break;
      case 3:
        list = _all
            .where((e) => e.status == 'BLOCKED' || e.status == 'DELETED')
            .toList();
        break;
      default:
        list = List.from(_all);
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.email.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  int get _pendingCount => _all.where((e) => e.status == 'PENDING').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Сотрудники'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
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
                    ]
                  ],
                ),
              ),
              const Tab(text: 'Активные'),
              const Tab(text: 'Заблокированные'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Поиск по имени или email',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: _filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Нет сотрудников',
                              style: TextStyle(
                                  color: AppColors.textHint,
                                  fontFamily: 'Inter'),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final emp = _filtered[i];
                              return _EmployeeCard(
                                emp: emp,
                                resolvedAvatarUrl: emp.avatarUrl != null
                                    ? ref.read(apiServiceProvider).mediaAbsoluteUrl(emp.avatarUrl)
                                    : null,
                                onApprove: emp.status == 'PENDING'
                                    ? () => _updateStatus(emp.id, 'ACTIVE')
                                    : null,
                                onReject: emp.status == 'PENDING'
                                    ? () => _updateStatus(emp.id, 'BLOCKED')
                                    : null,
                                onTap: () => _showEmployeeDetail(emp),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await ref
          .read(apiServiceProvider)
          .updateEmployee(id, {'status': status});
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'ACTIVE'
              ? 'Сотрудник подтверждён'
              : 'Сотрудник заблокирован'),
          backgroundColor:
              status == 'ACTIVE' ? AppColors.success : AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showEmployeeDetail(EmployeeModel emp) {
    final resolvedUrl = emp.avatarUrl != null
        ? ref.read(apiServiceProvider).mediaAbsoluteUrl(emp.avatarUrl)
        : null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeDetailSheet(
        emp: emp,
        resolvedAvatarUrl: resolvedUrl,
        onStatusChange: (status) => _updateStatus(emp.id, status),
        onRoleChange: (role) => _updateRole(emp.id, role),
        onEditProfile: () {
          Navigator.pop(context);
          _editEmployee(emp);
        },
      ),
    );
  }

  void _editEmployee(EmployeeModel emp) {
    final nameCtrl = TextEditingController(text: emp.fullName);
    final loginCtrl = TextEditingController(text: emp.username);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Редактировать профиль', style: TextStyle(fontFamily: 'Inter')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Полное имя'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: loginCtrl,
              decoration: const InputDecoration(labelText: 'Логин'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).updateEmployee(emp.id, {
                  if (nameCtrl.text.isNotEmpty && nameCtrl.text != emp.fullName) 'full_name': nameCtrl.text,
                  if (loginCtrl.text.isNotEmpty && loginCtrl.text != emp.username) 'username': loginCtrl.text,
                });
                if (mounted) {
                  Navigator.pop(ctx);
                  _load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Профиль обновлен'), backgroundColor: AppColors.success),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateRole(String id, String role) async {
    try {
      await ref.read(apiServiceProvider).updateEmployee(id, {'role': role});
      _load();
    } catch (_) {}
  }

}

// ─── Employee Card ────────────────────────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  final EmployeeModel emp;
  final String? resolvedAvatarUrl;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback onTap;

  const _EmployeeCard({
    required this.emp,
    this.resolvedAvatarUrl,
    this.onApprove,
    this.onReject,
    required this.onTap,
  });

  Color get _statusColor {
    switch (emp.status) {
      case 'ACTIVE':
        return AppColors.success;
      case 'PENDING':
        return AppColors.warning;
      case 'LEAVE':
        return AppColors.purple;
      case 'BLOCKED':
      case 'DELETED':
        return AppColors.error;
      default:
        return AppColors.textHint;
    }
  }

  Color get _statusBg {
    switch (emp.status) {
      case 'ACTIVE':
        return AppColors.successLight;
      case 'PENDING':
        return AppColors.warningLight;
      case 'LEAVE':
        return AppColors.purpleLight;
      case 'BLOCKED':
      case 'DELETED':
        return AppColors.errorLight;
      default:
        return AppColors.divider;
    }
  }

  String get _statusLabel {
    switch (emp.status) {
      case 'ACTIVE':
        return 'Активен';
      case 'PENDING':
        return 'Ожидает';
      case 'LEAVE':
        return 'В отпуске';
      case 'BLOCKED':
        return 'Заблокирован';
      case 'DELETED':
        return 'Удалён';
      default:
        return emp.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: resolvedAvatarUrl != null && resolvedAvatarUrl!.isNotEmpty
                        ? Image.network(
                            resolvedAvatarUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                emp.fullName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              emp.fullName.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emp.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            emp.displayRole,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                              fontFamily: 'Inter',
                            ),
                          ),
                          if (emp.teamName?.isNotEmpty == true) ...[
                            const Text(
                              ' · ',
                              style: TextStyle(
                                  color: AppColors.textHint,
                                  fontFamily: 'Inter'),
                            ),
                            Flexible(
                              child: Text(
                                emp.teamName!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                  fontFamily: 'Inter',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                              'Подтвердить',
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
      ),
    );
  }
}

// ─── Employee Detail Sheet ────────────────────────────────────────────────────

class _EmployeeDetailSheet extends StatelessWidget {
  final EmployeeModel emp;
  final String? resolvedAvatarUrl;
  final void Function(String) onStatusChange;
  final void Function(String) onRoleChange;
  final VoidCallback onEditProfile;

  const _EmployeeDetailSheet({
    required this.emp,
    this.resolvedAvatarUrl,
    required this.onStatusChange,
    required this.onRoleChange,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: resolvedAvatarUrl != null && resolvedAvatarUrl!.isNotEmpty
                        ? Image.network(
                            resolvedAvatarUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                emp.fullName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              emp.fullName.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                                fontFamily: 'Inter',
                              ),
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
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        emp.email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textHint,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, indent: 20, endIndent: 20),
          const SizedBox(height: 12),
          _actionTile(
            context,
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.success,
            label: 'Активировать',
            onTap: () {
              Navigator.pop(context);
              onStatusChange('ACTIVE');
            },
          ),
          _actionTile(
            context,
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.warning,
            label: 'Предупреждение',
            onTap: () {
              Navigator.pop(context);
              onStatusChange('WARNING');
            },
          ),
          _actionTile(
            context,
            icon: Icons.edit_rounded,
            iconColor: AppColors.primary,
            label: 'Редактировать профиль',
            onTap: onEditProfile,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context,
      {required IconData icon,
      required Color iconColor,
      required String label,
      required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        label,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            fontFamily: 'Inter'),
      ),
      onTap: onTap,
    );
  }
}

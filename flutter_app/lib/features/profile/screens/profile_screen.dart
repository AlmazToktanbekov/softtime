// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../providers.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/employee_schedule_model.dart';
import '../../../core/theme/app_theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  List<EmployeeScheduleModel> _schedules = [];
  EmployeeModel? _mentor;
  bool _loadingSchedule = true;
  bool _loadingMentor = false;
  bool _uploadingAvatar = false;
  int _avatarVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
    _loadMentor();
  }

  Future<void> _loadSchedule() async {
    try {
      final auth = ref.read(authProvider);
      final empId = auth.employee?.id ?? auth.user?.id;
      if (empId != null) {
        final schedules = await ref.read(apiServiceProvider).getEmployeeSchedules(empId);
        if (mounted) setState(() => _schedules = schedules);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSchedule = false);
    }
  }

  Future<void> _loadMentor() async {
    final auth = ref.read(authProvider);
    final mentorId = auth.user?.mentorId ?? auth.employee?.mentorId;
    if (mentorId == null) return;
    setState(() => _loadingMentor = true);
    try {
      final mentor = await ref.read(apiServiceProvider).getEmployee(mentorId);
      if (mounted) setState(() => _mentor = mentor);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMentor = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final newAvatarUrl = await ref.read(apiServiceProvider).uploadAvatar(File(picked.path));
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      ref.read(authProvider.notifier).updateAvatarUrl(newAvatarUrl);
      if (mounted) {
        setState(() => _avatarVersion++);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Фото профиля обновлено', style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ошибка загрузки: $e', style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final emp = auth.employee;
    final user = auth.user;
    final rawAvatar = user?.avatarUrl ?? emp?.avatarUrl;
    final avatarUrl = rawAvatar != null && rawAvatar.isNotEmpty
        ? '${ref.read(apiServiceProvider).mediaAbsoluteUrl(rawAvatar)}?v=$_avatarVersion'
        : null;
    final fullName = emp?.fullName ?? user?.fullName ?? user?.username ?? '-';
    final firstLetter = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Мой профиль')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Шапка профиля ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  // Аватар с кнопкой смены
                  GestureDetector(
                    onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Color(0x33FFFFFF),
                            shape: BoxShape.circle,
                          ),
                          child: _uploadingAvatar
                              ? const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                )
                              : ClipOval(
                                  child: avatarUrl != null && avatarUrl.isNotEmpty
                                      ? Image.network(
                                          avatarUrl,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Center(
                                            child: Text(
                                              firstLetter,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                                fontFamily: 'Inter',
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            firstLetter,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800,
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                        ),
                                ),
                        ),
                        // Иконка редактирования
                        if (!_uploadingAvatar)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (emp?.teamName != null && emp!.teamName!.isNotEmpty)
                          Text(
                            emp.teamName!,
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 13,
                              fontFamily: 'Inter',
                            ),
                          ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            user?.displayRole ?? _roleLabel(user?.role ?? 'employee'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Информация ────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: emp?.email ?? user?.email ?? '-',
                  ),
                  const Divider(height: 1, color: AppColors.divider, indent: 58),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Телефон',
                    value: emp?.phone ?? user?.phone ?? '-',
                  ),
                  const Divider(height: 1, color: AppColors.divider, indent: 58),
                  _InfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Логин',
                    value: user?.username ?? '-',
                  ),
                  const Divider(height: 1, color: AppColors.divider, indent: 58),
                  _InfoRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Дата найма',
                    value: _formatDate(emp?.hireDate ?? user?.hiredAt),
                  ),
                  // Команда
                  if (emp?.teamName != null || user?.teamId != null) ...[
                    const Divider(height: 1, color: AppColors.divider, indent: 58),
                    _InfoRowTappable(
                      icon: Icons.group_outlined,
                      label: 'Команда',
                      value: emp?.teamName ?? 'Моя команда',
                      onTap: () => context.push('/home/team'),
                    ),
                  ],
                  // Ментор
                  if (_mentor != null) ...[
                    const Divider(height: 1, color: AppColors.divider, indent: 58),
                    _InfoRow(
                      icon: Icons.school_outlined,
                      label: 'Ментор',
                      value: _mentor!.fullName,
                    ),
                  ] else if (_loadingMentor) ...[
                    const Divider(height: 1, color: AppColors.divider, indent: 58),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      child: Row(children: [
                        SizedBox(width: 36),
                        SizedBox(width: 14),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Загрузка ментора...',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 13,
                              fontFamily: 'Inter',
                            )),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── График работы ─────────────────────────────────────────────
            if (_loadingSchedule)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_schedules.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                      child: Text(
                        'Мой график работы',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    ...List.generate(7, (index) {
                      final dayName =
                          ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][index];
                      final sched = _schedules.firstWhere(
                        (s) => s.dayOfWeek == index,
                        orElse: () => EmployeeScheduleModel(
                            id: '', userId: '', dayOfWeek: index, isWorkday: false),
                      );
                      if (sched.id.isEmpty) {
                        return _ScheduleRow(
                            day: dayName, time: '-', isWorkday: false);
                      }
                      final timeStr =
                          sched.isWorkday && sched.startTime != null && sched.endTime != null
                              ? '${sched.startTime!.substring(0, 5)}–${sched.endTime!.substring(0, 5)}'
                              : 'Выходной';
                      return _ScheduleRow(
                          day: dayName,
                          time: timeStr,
                          isWorkday: sched.isWorkday);
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Кнопки ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Выйти из аккаунта',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final d = DateTime.parse(raw);
      const months = [
        '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN': return 'Администратор';
      case 'SUPER_ADMIN': return 'Суперадмин';
      case 'TEAM_LEAD': return 'Ментор';
      case 'INTERN': return 'Стажёр';
      default: return 'Сотрудник';
    }
  }
}

// ─── Subwidgets ────────────────────────────────────────────────────────────────

class _ScheduleRow extends StatelessWidget {
  final String day;
  final String time;
  final bool isWorkday;

  const _ScheduleRow({required this.day, required this.time, required this.isWorkday});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(day,
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: AppColors.textHint, fontFamily: 'Inter',
                )),
          ),
          const SizedBox(width: 14),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isWorkday ? AppColors.success : AppColors.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(time,
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter',
                  color: isWorkday ? AppColors.textPrimary : AppColors.textHint,
                )),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 12, color: AppColors.textHint, fontFamily: 'Inter',
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary, fontFamily: 'Inter',
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRowTappable extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InfoRowTappable({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                        fontSize: 12, color: AppColors.textHint, fontFamily: 'Inter',
                      )),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppColors.primary, fontFamily: 'Inter',
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }
}

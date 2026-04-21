import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_provider.dart';

class AdminMoreScreen extends ConsumerWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final name = auth.user?.fullName ?? auth.user?.username ?? 'Admin';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Управление'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1877F2), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        auth.user?.displayRole ?? 'Администратор',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xCCFFFFFF),
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
          const _SectionTitle('Контент'),
          const SizedBox(height: 8),

          _ManageItem(
            icon: Icons.article_rounded,
            iconColor: AppColors.primary,
            iconBg: AppColors.primaryLight,
            title: 'Новости',
            subtitle: 'Создание и управление новостями',
            onTap: () => context.push('/admin/news'),
          ),

          const SizedBox(height: 20),
          const _SectionTitle('Дежурство'),
          const SizedBox(height: 8),

          _ManageItem(
            icon: Icons.assignment_ind_rounded,
            iconColor: AppColors.purple,
            iconBg: AppColors.purpleLight,
            title: 'Назначение дежурств',
            subtitle: 'Управление графиком дежурств',
            onTap: () => context.push('/admin/duty'),
          ),

          const SizedBox(height: 20),
          const _SectionTitle('Сотрудники'),
          const SizedBox(height: 8),

          _ManageItem(
            icon: Icons.calendar_month_rounded,
            iconColor: AppColors.success,
            iconBg: AppColors.successLight,
            title: 'Расписание',
            subtitle: 'Рабочий график каждого сотрудника',
            onTap: () => context.push('/admin/schedule'),
          ),
          const SizedBox(height: 8),
          _ManageItem(
            icon: Icons.event_note_rounded,
            iconColor: AppColors.warning,
            iconBg: AppColors.warningLight,
            title: 'Заявки на отпуск',
            subtitle: 'Одобрение и отклонение заявок',
            onTap: () => context.push('/admin/requests'),
          ),

          const SizedBox(height: 20),
          const _SectionTitle('Система'),
          const SizedBox(height: 8),

          _ManageItem(
            icon: Icons.qr_code_rounded,
            iconColor: AppColors.textPrimary,
            iconBg: AppColors.divider,
            title: 'QR-коды',
            subtitle: 'Просмотр и генерация QR офиса',
            onTap: () => context.push('/admin/qr'),
          ),
          const SizedBox(height: 8),
          _ManageItem(
            icon: Icons.wifi_rounded,
            iconColor: AppColors.primary,
            iconBg: AppColors.primaryLight,
            title: 'Офисные сети',
            subtitle: 'Управление разрешёнными IP/подсетями',
            onTap: () => context.push('/admin/networks'),
          ),

          const SizedBox(height: 20),
          const _SectionTitle('Аккаунт'),
          const SizedBox(height: 8),

          _ManageItem(
            icon: Icons.logout_rounded,
            iconColor: AppColors.error,
            iconBg: AppColors.errorLight,
            title: 'Выйти',
            subtitle: 'Завершить сессию',
            onTap: () => _logout(context, ref),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        content:
            const Text('Вы уверены, что хотите выйти?',
                style: TextStyle(fontFamily: 'Inter')),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) context.go('/login');
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textHint,
        fontFamily: 'Inter',
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ManageItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManageItem({
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
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
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}

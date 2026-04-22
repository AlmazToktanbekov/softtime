import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(badgeProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(badgeProvider.notifier).refresh();
    }
  }

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/home/profile')) return 4;
    if (loc.startsWith('/home/requests')) return 3;
    if (loc.startsWith('/news')) return 2;
    if (loc.startsWith('/duty')) return 1;
    return 0;
  }

  void _onNavTap(BuildContext context, int tabIndex) {
    final notifier = ref.read(badgeProvider.notifier);
    switch (tabIndex) {
      case 0:
        context.go('/home');
      case 1:
        notifier.clearDuty();
        context.go('/duty');
      case 2:
        context.go('/news');
      case 3:
        notifier.clearRequests();
        context.go('/home/requests');
      case 4:
        context.go('/home/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    final badges = ref.watch(badgeProvider);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Главная',
                  isActive: idx == 0,
                  onTap: () => _onNavTap(context, 0),
                ),
                _NavItem(
                  icon: Icons.cleaning_services_outlined,
                  activeIcon: Icons.cleaning_services_rounded,
                  label: 'Дежурство',
                  isActive: idx == 1,
                  hasBadge: badges.duty,
                  onTap: () => _onNavTap(context, 1),
                ),
                _NavItem(
                  icon: Icons.article_outlined,
                  activeIcon: Icons.article_rounded,
                  label: 'Новости',
                  isActive: idx == 2,
                  onTap: () => _onNavTap(context, 2),
                ),
                _NavItem(
                  icon: Icons.event_note_outlined,
                  activeIcon: Icons.event_note_rounded,
                  label: 'Заявки',
                  isActive: idx == 3,
                  hasBadge: badges.requests,
                  onTap: () => _onNavTap(context, 3),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Профиль',
                  isActive: idx == 4,
                  onTap: () => _onNavTap(context, 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final bool hasBadge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    this.hasBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isActive ? activeIcon : icon,
                    key: ValueKey(isActive),
                    size: 22,
                    color: isActive ? AppColors.primary : AppColors.textHint,
                  ),
                ),
                if (hasBadge)
                  Positioned(
                    top: -3,
                    right: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.primary : AppColors.textHint,
                fontFamily: 'Inter',
              ),
              child: Text(label),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 16 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/user_model.dart';
import '../../../providers.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  TeamModel? _team;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    setState(() { _loading = true; _error = null; });
    try {
      final auth = ref.read(authProvider);
      final teamId = auth.user?.teamId ?? auth.employee?.teamId;
      final api = ref.read(apiServiceProvider);
      if (teamId != null) {
        final team = await api.getTeam(teamId);
        if (mounted) setState(() => _team = team);
      } else {
        // Попробуем через /teams/my/team
        final team = await api.getMyTeam();
        if (mounted) setState(() => _team = team);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Команда не найдена или вы не в команде');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_team?.name ?? 'Моя команда'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadTeam,
        child: _loading
            ? _buildShimmer()
            : _error != null
                ? _buildEmpty()
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final team = _team!;
    final auth = ref.read(authProvider);
    final myId = auth.user?.id;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Карточка команды ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.group_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
                          ),
                        ),
                        if (team.description != null &&
                            team.description!.isNotEmpty)
                          Text(
                            team.description!,
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 13,
                              fontFamily: 'Inter',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.people_outline_rounded,
                    label: '${team.memberCount} участн.',
                  ),
                  const SizedBox(width: 10),
                  if (team.mentorName != null)
                    _StatChip(
                      icon: Icons.school_outlined,
                      label: 'Ментор: ${team.mentorName}',
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Ментор ───────────────────────────────────────────────────
        if (team.mentorName != null) ...[
          const _SectionLabel(text: 'Ментор'),
          const SizedBox(height: 10),
          _MemberTile(
            name: team.mentorName!,
            role: 'Ментор',
            isMe: team.mentorId == myId,
            isMentor: true,
          ),
          const SizedBox(height: 20),
        ],

        // ── Участники ────────────────────────────────────────────────
        _SectionLabel(text: 'Участники (${team.members.length})'),
        const SizedBox(height: 10),
        if (team.members.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text('Нет участников',
                  style: TextStyle(
                      color: AppColors.textHint, fontFamily: 'Inter')),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: team.members.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider, indent: 68),
              itemBuilder: (_, i) {
                final m = team.members[i];
                return _MemberTile(
                  name: m.fullName,
                  role: _roleLabel(m.role),
                  status: m.status,
                  avatarUrl: m.avatarUrl,
                  isMe: m.id == myId,
                );
              },
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
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
              child: const Icon(Icons.group_off_rounded,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Вы не в команде',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Команды создаются администратором',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Shimmer.fromColors(
          baseColor: const Color(0xFFEEEEEE),
          highlightColor: const Color(0xFFFAFAFA),
          child: Container(
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Shimmer.fromColors(
          baseColor: const Color(0xFFEEEEEE),
          highlightColor: const Color(0xFFFAFAFA),
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }

  String _roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'TEAM_LEAD': return 'Ментор';
      case 'INTERN': return 'Стажёр';
      case 'ADMIN': return 'Администратор';
      default: return 'Сотрудник';
    }
  }
}

// ─── Subwidgets ────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        fontFamily: 'Inter',
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              )),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final String name;
  final String role;
  final String? status;
  final String? avatarUrl;
  final bool isMe;
  final bool isMentor;

  const _MemberTile({
    required this.name,
    required this.role,
    this.status,
    this.avatarUrl,
    this.isMe = false,
    this.isMentor = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final avatarBg = isMentor ? const Color(0xFF7B61FF) : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Аватар
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: avatarBg.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(initials,
                            style: TextStyle(
                              color: avatarBg,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              fontFamily: 'Inter',
                            )),
                      ),
                    )
                  : Center(
                      child: Text(initials,
                          style: TextStyle(
                            color: avatarBg,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            fontFamily: 'Inter',
                          )),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Вы',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              fontFamily: 'Inter',
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(role,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontFamily: 'Inter',
                    )),
              ],
            ),
          ),
          // Статус
          if (status != null)
            _StatusDot(status: status!),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        color = AppColors.success;
        label = 'Активен';
        break;
      case 'LEAVE':
        color = const Color(0xFF7B61FF);
        label = 'Отпуск';
        break;
      case 'BLOCKED':
        color = AppColors.error;
        label = 'Заблокирован';
        break;
      default:
        color = AppColors.textHint;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'Inter',
          )),
    );
  }
}

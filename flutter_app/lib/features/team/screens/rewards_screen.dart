import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _leaderboard = [];
  int _myPoints = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getMyPoints(),
        ApiService().getRewards(),
        ApiService().getLeaderboard(),
      ]);
      setState(() {
        _myPoints = results[0] as int;
        _rewards = results[1] as List<Map<String, dynamic>>;
        _leaderboard = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('🏆 Геймификация', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Мои очки'),
            Tab(text: 'Магазин'),
            Tab(text: 'Лидерборд'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPointsTab(),
                _buildShopTab(),
                _buildLeaderboardTab(),
              ],
            ),
    );
  }

  Widget _buildPointsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Points card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFFB347)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(
                  '$_myPoints',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Soft-коинов',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // How to earn points
          _SectionTitle('Как заработать очки'),
          const SizedBox(height: 8),
          _InfoCard('✅ Без опозданий', '+10 очков за день'),
          _InfoCard('🙌 Кудос получен', '+5 очков'),
          _InfoCard('📋 Задача выполнена', '+15 очков'),
          const SizedBox(height: 16),
          _SectionTitle('На что потратить'),
          const SizedBox(height: 8),
          _InfoCard('☕ Бесплатный обед', '50 очков'),
          _InfoCard('😴 Дополнительный отгул', '200 очков'),
          _InfoCard('👕 Мерч компании', '150 очков'),
        ],
      ),
    );
  }

  Widget _buildShopTab() {
    if (_rewards.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🎁', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Призов пока нет', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Администратор добавит призы'),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _rewards.length,
      itemBuilder: (ctx, i) => _RewardCard(
        reward: _rewards[i],
        myPoints: _myPoints,
        onClaim: () => _claimReward(_rewards[i]),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _leaderboard.length,
      itemBuilder: (ctx, i) {
        final entry = _leaderboard[i];
        final medals = ['🥇', '🥈', '🥉'];
        final medal = i < 3 ? medals[i] : '${i + 1}.';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: i == 0 ? const Color(0xFFFFD700).withOpacity(0.1) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: i == 0 ? const Color(0xFFFFD700).withOpacity(0.5) : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(medal, style: const TextStyle(fontSize: 22), textAlign: TextAlign.center),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: entry['avatar_url'] != null ? NetworkImage(entry['avatar_url']) : null,
                child: entry['avatar_url'] == null
                    ? Text(
                        (entry['full_name'] as String? ?? '?')[0].toUpperCase(),
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(entry['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${entry['points']} 🏆',
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _claimReward(Map<String, dynamic> reward) async {
    final cost = reward['cost_points'] as int? ?? 0;
    if (_myPoints < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Недостаточно очков. Нужно $cost, у вас $_myPoints'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${reward['emoji'] ?? '🎁'} ${reward['title']}'),
        content: Text('Потратить $cost очков?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Обменять', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService().claimReward(reward['id']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Запрос на "${reward['title']}" отправлен!')),
        );
        _loadData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _RewardCard extends StatelessWidget {
  final Map<String, dynamic> reward;
  final int myPoints;
  final VoidCallback onClaim;
  const _RewardCard({required this.reward, required this.myPoints, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final cost = reward['cost_points'] as int? ?? 0;
    final canAfford = myPoints >= cost;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: canAfford ? AppColors.primary.withOpacity(0.3) : AppColors.divider,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(reward['emoji'] ?? '🎁', style: const TextStyle(fontSize: 40)),
          Text(
            reward['title'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (reward['description'] != null)
            Text(reward['description'], style: TextStyle(color: AppColors.textHint, fontSize: 11), textAlign: TextAlign.center),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: canAfford ? AppColors.primary.withOpacity(0.1) : AppColors.divider.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$cost 🏆',
              style: TextStyle(
                color: canAfford ? AppColors.primary : AppColors.textHint,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canAfford ? AppColors.primary : AppColors.divider,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: canAfford ? onClaim : null,
              child: Text(
                canAfford ? 'Обменять' : 'Мало очков',
                style: TextStyle(
                  color: canAfford ? Colors.white : AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _InfoCard(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 14)),
          Text(subtitle, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

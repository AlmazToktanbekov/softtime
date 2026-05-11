import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  int _myPoints = 0;
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _leaderboard = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
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
        title: const Text('🏆 Магазин призов', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBalanceCard(),
                    const SizedBox(height: 24),
                    const Text('🥇 Лидерборд', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildLeaderboard(),
                    const SizedBox(height: 24),
                    const Text('🎁 Доступные призы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildRewardsGrid(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Text('Ваш баланс', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🪙 ', style: TextStyle(fontSize: 32)),
              Text('$_myPoints', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
            ],
          ),
          const Text('баллов', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLeaderboard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(
        children: _leaderboard.asMap().entries.map((e) {
          final i = e.key;
          final user = e.value;
          final isTop3 = i < 3;
          final medals = ['🥇', '🥈', '🥉'];
          return ListTile(
            leading: SizedBox(
              width: 32,
              child: Text(isTop3 ? medals[i] : '${i + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            title: Text(user['full_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text('${user['points']} 🪙', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRewardsGrid() {
    if (_rewards.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Призов пока нет', style: TextStyle(color: AppColors.textHint)),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: _rewards.length,
      itemBuilder: (ctx, i) => _RewardCard(
        reward: _rewards[i],
        canAfford: _myPoints >= (_rewards[i]['cost_points'] as int),
        onClaim: () => _loadData(),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final Map<String, dynamic> reward;
  final bool canAfford;
  final VoidCallback onClaim;
  const _RewardCard({required this.reward, required this.canAfford, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(child: Text(reward['emoji'] ?? '🎁', style: const TextStyle(fontSize: 48))),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(reward['title'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 2),
                const SizedBox(height: 8),
                Text('${reward['cost_points']} 🪙', style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford ? AppColors.primary : Colors.grey.shade300,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: canAfford ? () => _claim(context) : null,
                    child: Text('Купить', style: TextStyle(color: canAfford ? Colors.white : Colors.grey, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _claim(BuildContext context) async {
    try {
      await ApiService().claimReward(reward['id']);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Запрос на "${reward['title']}" отправлен!')));
        onClaim();
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }
}

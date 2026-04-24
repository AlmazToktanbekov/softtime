import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_provider.dart';

class InternProgressScreen extends ConsumerStatefulWidget {
  const InternProgressScreen({super.key});

  @override
  ConsumerState<InternProgressScreen> createState() => _InternProgressScreenState();
}

class _InternProgressScreenState extends ConsumerState<InternProgressScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _diary = [];
  List<Map<String, dynamic>> _evaluations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = ref.read(authProvider).user;
      final results = await Future.wait([
        ApiService().getMyDiary(),
        if (user != null) ApiService().getInternEvaluations(user.id),
      ]);
      setState(() {
        _diary = results[0];
        _evaluations = results.length > 1 ? results[1] : [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final hiredAtStr = user?.hiredAt;
    DateTime? hiredAtDate;
    if (hiredAtStr != null) {
      try { hiredAtDate = DateTime.parse(hiredAtStr); } catch (_) {}
    }
    final daysWorked = hiredAtDate != null
        ? DateTime.now().difference(hiredAtDate).inDays
        : 0;
    final probationDays = 30;
    final progress = (daysWorked / probationDays).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мой прогресс', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Дневник'),
            Tab(text: 'Оценки'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    _buildProgressCard(daysWorked, probationDays, progress),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDiaryTab(),
                          _buildEvaluationsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _showAddDiaryDialog,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildProgressCard(int daysWorked, int total, double progress) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🚀 Испытательный срок',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$daysWorked из $total дней',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 10,
            ),
          ),
          if (progress >= 1.0) ...[
            const SizedBox(height: 8),
            const Text(
              '🎉 Испытательный срок пройден!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiaryTab() {
    if (_diary.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📔', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Дневник пуст', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Нажмите + чтобы добавить запись', style: TextStyle(color: AppColors.textHint)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _diary.length,
        itemBuilder: (ctx, i) => _DiaryCard(entry: _diary[i]),
      ),
    );
  }

  Widget _buildEvaluationsTab() {
    if (_evaluations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📊', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Оценок пока нет', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _evaluations.length,
      itemBuilder: (ctx, i) => _EvaluationCard(evaluation: _evaluations[i]),
    );
  }

  void _showAddDiaryDialog() {
    final learnedCtrl = TextEditingController();
    final diffCtrl = TextEditingController();
    final plansCtrl = TextEditingController();
    int mood = 3;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📔 Запись в дневник', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: learnedCtrl,
                  decoration: const InputDecoration(labelText: 'Что нового узнал сегодня? *'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: diffCtrl,
                  decoration: const InputDecoration(labelText: 'Трудности'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: plansCtrl,
                  decoration: const InputDecoration(labelText: 'Планы на завтра'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('Настроение:', style: TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['😞', '😐', '🙂', '😊', '🤩'].asMap().entries.map((e) {
                    final val = e.key + 1;
                    return GestureDetector(
                      onTap: () => setModalState(() => mood = val),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: mood == val ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(e.value, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (learnedCtrl.text.trim().isEmpty) return;
                      try {
                        final today = DateTime.now();
                        final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                        await ApiService().saveDiaryEntry({
                          'diary_date': dateStr,
                          'learned_today': learnedCtrl.text.trim(),
                          'difficulties': diffCtrl.text.trim().isEmpty ? null : diffCtrl.text.trim(),
                          'plans_tomorrow': plansCtrl.text.trim().isEmpty ? null : plansCtrl.text.trim(),
                          'mood': mood,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      }
                    },
                    child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _DiaryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final moodEmojis = ['', '😞', '😐', '🙂', '😊', '🤩'];
    final mood = entry['mood'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry['diary_date'] ?? '',
                style: TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
              if (mood > 0) Text(moodEmojis[mood], style: const TextStyle(fontSize: 22)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('✅ Узнал:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(entry['learned_today'] ?? '', style: const TextStyle(fontSize: 14)),
          if (entry['difficulties'] != null && entry['difficulties'].toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('🚧 Трудности:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(entry['difficulties'], style: const TextStyle(fontSize: 14)),
          ],
          if (entry['plans_tomorrow'] != null && entry['plans_tomorrow'].toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('📋 Планы:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(entry['plans_tomorrow'], style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

class _EvaluationCard extends StatelessWidget {
  final Map<String, dynamic> evaluation;
  const _EvaluationCard({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final m = evaluation['motivation_score'] as int? ?? 0;
    final k = evaluation['knowledge_score'] as int? ?? 0;
    final c = evaluation['communication_score'] as int? ?? 0;
    final avg = (m + k + c) / 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(evaluation['eval_period'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${avg.toStringAsFixed(1)}/5.0', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ScoreRow(label: '💪 Мотивация', score: m),
          _ScoreRow(label: '📚 Знания', score: k),
          _ScoreRow(label: '💬 Общение', score: c),
          if (evaluation['comment'] != null && evaluation['comment'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"${evaluation['comment']}"', style: TextStyle(color: AppColors.textHint, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;
  const _ScoreRow({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / 5.0,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score/5', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

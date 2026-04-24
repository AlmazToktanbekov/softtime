import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';

class MentorDashboardScreen extends ConsumerStatefulWidget {
  const MentorDashboardScreen({super.key});

  @override
  ConsumerState<MentorDashboardScreen> createState() => _MentorDashboardScreenState();
}

class _MentorDashboardScreenState extends ConsumerState<MentorDashboardScreen> {
  List<Map<String, dynamic>> _mentees = [];
  bool _loading = true;
  String? _error;
  String? _selectedInternId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final mentees = await ApiService().getMyMentees();
      setState(() { _mentees = mentees; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мои подопечные', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _mentees.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('👥', style: TextStyle(fontSize: 48)),
                          SizedBox(height: 12),
                          Text('Нет подопечных стажеров', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _mentees.length,
                        itemBuilder: (ctx, i) => _MenteeCard(
                          mentee: _mentees[i],
                          onEvaluate: () => _showEvaluateDialog(_mentees[i]),
                          onViewDiary: () => _showDiary(_mentees[i]),
                        ),
                      ),
                    ),
    );
  }

  void _showEvaluateDialog(Map<String, dynamic> mentee) {
    int motivation = 3, knowledge = 3, communication = 3;
    final commentCtrl = TextEditingController();
    final now = DateTime.now();
    // ISO week
    final weekNum = ((now.difference(DateTime(now.year, 1, 1)).inDays + DateTime(now.year, 1, 1).weekday) / 7).ceil();
    final period = '${now.year}-W${weekNum.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📊 Оценка: ${mentee['full_name']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text('Период: $period', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                const SizedBox(height: 20),
                _SliderRow(
                  label: '💪 Мотивация',
                  value: motivation,
                  onChanged: (v) => setModal(() => motivation = v),
                ),
                _SliderRow(
                  label: '📚 Знания',
                  value: knowledge,
                  onChanged: (v) => setModal(() => knowledge = v),
                ),
                _SliderRow(
                  label: '💬 Общение',
                  value: communication,
                  onChanged: (v) => setModal(() => communication = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentCtrl,
                  decoration: const InputDecoration(labelText: 'Комментарий (необязательно)'),
                  maxLines: 3,
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
                      try {
                        await ApiService().createEvaluation({
                          'intern_id': mentee['id'],
                          'eval_period': period,
                          'motivation_score': motivation,
                          'knowledge_score': knowledge,
                          'communication_score': communication,
                          'comment': commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ Оценка отправлена стажеру')),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      }
                    },
                    child: const Text('Отправить оценку', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDiary(Map<String, dynamic> mentee) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, scroll) => _InternDiaryView(
          internId: mentee['id'],
          internName: mentee['full_name'],
          scroll: scroll,
        ),
      ),
    );
  }
}

class _MenteeCard extends StatelessWidget {
  final Map<String, dynamic> mentee;
  final VoidCallback onEvaluate;
  final VoidCallback onViewDiary;

  const _MenteeCard({required this.mentee, required this.onEvaluate, required this.onViewDiary});

  @override
  Widget build(BuildContext context) {
    final done = mentee['tasks_done'] as int? ?? 0;
    final total = mentee['tasks_total'] as int? ?? 0;
    final checkedIn = mentee['checked_in_today'] as bool? ?? false;
    final daysWorked = mentee['days_worked'] as int? ?? 0;
    final taskProgress = total > 0 ? done / total : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: mentee['avatar_url'] != null ? NetworkImage(mentee['avatar_url']) : null,
                child: mentee['avatar_url'] == null
                    ? Text(
                        (mentee['full_name'] as String? ?? '?')[0].toUpperCase(),
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mentee['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: checkedIn ? Colors.green : AppColors.error),
                        const SizedBox(width: 4),
                        Text(
                          checkedIn ? 'На работе' : 'Не отмечался',
                          style: TextStyle(
                            fontSize: 12,
                            color: checkedIn ? Colors.green : AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('$daysWorked дн. работы', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Задачи: $done/$total', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
              Text('${(taskProgress * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: taskProgress,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onViewDiary,
                  icon: const Icon(Icons.book_outlined, size: 16),
                  label: const Text('Дневник', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onEvaluate,
                  icon: const Icon(Icons.star_outline, size: 16, color: Colors.white),
                  label: const Text('Оценить', style: TextStyle(fontSize: 13, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _SliderRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('$value / 5', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          activeColor: AppColors.primary,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

class _InternDiaryView extends StatefulWidget {
  final String internId;
  final String internName;
  final ScrollController scroll;
  const _InternDiaryView({required this.internId, required this.internName, required this.scroll});

  @override
  State<_InternDiaryView> createState() => _InternDiaryViewState();
}

class _InternDiaryViewState extends State<_InternDiaryView> {
  List<Map<String, dynamic>> _diary = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService().getInternDiary(widget.internId);
      setState(() { _diary = d; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('📔 Дневник: ${widget.internName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_diary.isEmpty)
          const Expanded(child: Center(child: Text('Дневник пуст')))
        else
          Expanded(
            child: ListView.builder(
              controller: widget.scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _diary.length,
              itemBuilder: (ctx, i) {
                final e = _diary[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e['diary_date'] ?? '', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(e['learned_today'] ?? '', style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

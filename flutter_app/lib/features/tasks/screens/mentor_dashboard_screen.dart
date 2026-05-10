import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import 'mentor_evaluation_screen.dart';

class MentorDashboardScreen extends ConsumerStatefulWidget {
  const MentorDashboardScreen({super.key});

  @override
  ConsumerState<MentorDashboardScreen> createState() => _MentorDashboardScreenState();
}

class _MentorDashboardScreenState extends ConsumerState<MentorDashboardScreen> {
  List<Map<String, dynamic>> _mentees = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService().getMyMentees();
      setState(() { _mentees = data; _loading = false; });
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
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _mentees.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _mentees.length,
                      itemBuilder: (ctx, i) => _MenteeCard(
                        mentee: _mentees[i],
                        onRefresh: _loadData,
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('👨‍🎓', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text('У вас пока нет подопечных', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Администратор назначит их вам в панели управления', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _MenteeCard extends StatelessWidget {
  final Map<String, dynamic> mentee;
  final VoidCallback onRefresh;
  const _MenteeCard({required this.mentee, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final tasksTotal = mentee['tasks_total'] ?? 0;
    final tasksDone = mentee['tasks_done'] ?? 0;
    final progress = tasksTotal > 0 ? (tasksDone / tasksTotal) : 0.0;
    final inOffice = mentee['checked_in_today'] ?? false;
    final latestEval = mentee['latest_evaluation'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MentorEvaluationScreen(mentee: mentee),
              ),
            );
            onRefresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: mentee['avatar_url'] != null
                          ? NetworkImage(ApiService().mediaAbsoluteUrl(mentee['avatar_url']))
                          : null,
                      child: mentee['avatar_url'] == null
                          ? Text(mentee['full_name'][0], style: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(mentee['full_name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: inOffice ? Colors.green : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(inOffice ? 'В офисе' : 'Не в офисе', style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Задачи стажера:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.divider,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$tasksDone/$tasksTotal', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                if (latestEval != null) ...[
                   _buildEvalBadge(latestEval),
                ] else ...[
                  const Text('⚠️ Нет оценок', style: TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEvalBadge(Map<String, dynamic> eval) {
    final m = eval['motivation_score'] ?? 0;
    final k = eval['knowledge_score'] ?? 0;
    final c = eval['communication_score'] ?? 0;
    final avg = (m + k + c) / 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Последняя оценка: ', style: TextStyle(fontSize: 12)),
          Text(avg.toStringAsFixed(1), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
          const Text(' / 5.0', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class MentorEvaluationScreen extends StatefulWidget {
  final Map<String, dynamic> mentee;
  const MentorEvaluationScreen({super.key, required this.mentee});

  @override
  State<MentorEvaluationScreen> createState() => _MentorEvaluationScreenState();
}

class _MentorEvaluationScreenState extends State<MentorEvaluationScreen> {
  int _motivation = 3;
  int _knowledge = 3;
  int _communication = 3;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      // Период в формате ГГГГ-Wнн (неделя)
      final weekNum = ((now.day + 7) / 7).floor();
      final period = '${now.year}-W${weekNum.toString().padLeft(2, '0')}';

      await ApiService().createEvaluation({
        'intern_id': widget.mentee['id'],
        'eval_period': period,
        'motivation_score': _motivation,
        'knowledge_score': _knowledge,
        'communication_score': _communication,
        'comment': _commentCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Оценка успешно сохранена'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Оценка: ${widget.mentee['full_name'].split(' ')[0]}'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),
            const Text('Критерии оценки (1-5)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildScoreSlider('💪 Мотивация', _motivation, (v) => setState(() => _motivation = v)),
            _buildScoreSlider('📚 Знания и навыки', _knowledge, (v) => setState(() => _knowledge = v)),
            _buildScoreSlider('💬 Коммуникация', _communication, (v) => setState(() => _communication = v)),
            const SizedBox(height: 24),
            const Text('Комментарий ментора', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Что стажеру стоит подтянуть? Что получается хорошо?',
                fillColor: AppColors.surface,
                filled: true,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Сохранить оценку', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: widget.mentee['avatar_url'] != null
                ? NetworkImage(ApiService().mediaAbsoluteUrl(widget.mentee['avatar_url']))
                : null,
            child: widget.mentee['avatar_url'] == null ? const Icon(Icons.person) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.mentee['full_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Дней на стажировке: ${widget.mentee['days_worked']}', style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreSlider(String label, int value, Function(int) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('$value/5', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1, max: 5,
          divisions: 4,
          activeColor: AppColors.primary,
          onChanged: (v) => onChanged(v.toInt()),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

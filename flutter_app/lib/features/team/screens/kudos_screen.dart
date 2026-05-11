import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class KudosScreen extends ConsumerStatefulWidget {
  const KudosScreen({super.key});

  @override
  ConsumerState<KudosScreen> createState() => _KudosScreenState();
}

class _KudosScreenState extends ConsumerState<KudosScreen> {
  List<Map<String, dynamic>> _kudos = [];
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
      final data = await ApiService().getKudos();
      setState(() { _kudos = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('🙌 Доска благодарностей', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _kudos.length,
                    itemBuilder: (ctx, i) => _KudosCard(kudo: _kudos[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSendKudosDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.favorite, color: Colors.white),
        label: const Text('Сказать спасибо', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showSendKudosDialog() async {
    final employees = await ApiService().getUsers();
    if (!mounted) return;

    String? selectedUserId;
    final messageCtrl = TextEditingController();
    String selectedEmoji = '🙌';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                const Text('🎁 Отправить кудос', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Кому?'),
                  items: employees.map((e) => DropdownMenuItem(
                    value: e['id'].toString(),
                    child: Text(e['full_name']),
                  )).toList(),
                  onChanged: (v) => setModalState(() => selectedUserId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageCtrl,
                  decoration: const InputDecoration(labelText: 'Сообщение благодарности'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('Реакция:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['🙌', '🚀', '🌟', '💡', '🔥', '🏆'].map((e) => GestureDetector(
                    onTap: () => setModalState(() => selectedEmoji = e),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selectedEmoji == e ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      if (selectedUserId == null || messageCtrl.text.isEmpty) return;
                      try {
                        await ApiService().sendKudos(selectedUserId!, messageCtrl.text, selectedEmoji);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ваша благодарность отправлена! +5 очков коллеге'), backgroundColor: Colors.green));
                      } catch (e) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                      }
                    },
                    child: const Text('Отправить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

class _KudosCard extends StatelessWidget {
  final Map<String, dynamic> kudo;
  const _KudosCard({required this.kudo});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              Text(kudo['emoji'] ?? '🙌', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black, fontSize: 14),
                    children: [
                      TextSpan(text: kudo['from_user_name'] ?? 'Кто-то', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: ' поблагодарил(а) '),
                      TextSpan(text: kudo['to_user_name'] ?? 'Коллегу', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '"${kudo['message']}"',
              style: const TextStyle(
                color: AppColors.textPrimary, 
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              kudo['created_at'] != null ? kudo['created_at'].toString().split(' ')[0] : '',
              style: const TextStyle(color: AppColors.textHint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

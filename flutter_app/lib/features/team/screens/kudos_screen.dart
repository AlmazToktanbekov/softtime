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
      final kudos = await ApiService().getKudos();
      setState(() { _kudos = kudos; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('🙌 Кудосы', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _kudos.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _kudos.length,
                        itemBuilder: (ctx, i) => _KudosCard(kudos: _kudos[i]),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSendKudosDialog,
        backgroundColor: const Color(0xFFFF6B35),
        icon: const Icon(Icons.favorite, color: Colors.white),
        label: const Text('Поблагодарить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🙌', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('Будьте первым!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Поблагодарите коллегу за помощь',
            style: TextStyle(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  void _showSendKudosDialog() async {
    // Load users to pick from
    final users = await ApiService().getUsers();
    if (!mounted) return;

    final emojis = ['🙌', '🔥', '⭐', '💪', '🎉', '❤️', '👏', '🚀'];
    String selectedEmoji = '🙌';
    String? selectedUserId;
    String? selectedUserName;
    final msgCtrl = TextEditingController();

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
                const Text('🙌 Отправить кудос', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                // User picker
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: selectedUserId,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    hint: const Text('Выберите коллегу'),
                    items: users.map((u) => DropdownMenuItem<String>(
                      value: u['id'] as String,
                      child: Text(u['full_name'] as String? ?? ''),
                    )).toList(),
                    onChanged: (v) {
                      setModal(() {
                        selectedUserId = v;
                        selectedUserName = users.firstWhere((u) => u['id'] == v)['full_name'];
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Выберите эмодзи:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: emojis.map((e) => GestureDetector(
                    onTap: () => setModal(() => selectedEmoji = e),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selectedEmoji == e ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selectedEmoji == e ? AppColors.primary : AppColors.divider,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: msgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Напишите благодарность *',
                    hintText: 'Спасибо за помощь с проектом!',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (selectedUserId == null || msgCtrl.text.trim().isEmpty) return;
                      try {
                        await ApiService().sendKudos(selectedUserId!, msgCtrl.text.trim(), selectedEmoji);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$selectedEmoji Кудос отправлен $selectedUserName!')),
                        );
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      }
                    },
                    child: const Text('Отправить 🙌', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
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
  final Map<String, dynamic> kudos;
  const _KudosCard({required this.kudos});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6B35).withOpacity(0.05),
            Colors.transparent,
          ],
        ),
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(kudos['emoji'] ?? '🙌', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${kudos['from_user_name'] ?? 'Кто-то'} → ${kudos['to_user_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      _formatDate(kudos['created_at']),
                      style: TextStyle(color: AppColors.textHint, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '"${kudos['message']}"',
            style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }
}

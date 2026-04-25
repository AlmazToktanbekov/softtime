import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class TeamCalendarScreen extends ConsumerStatefulWidget {
  const TeamCalendarScreen({super.key});

  @override
  ConsumerState<TeamCalendarScreen> createState() => _TeamCalendarScreenState();
}

class _TeamCalendarScreenState extends ConsumerState<TeamCalendarScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().getTodayOfficeStatus();
      setState(() { _status = data; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('📅 Календарь команды', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.surface,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'В офисе'),
              Tab(text: 'Ушли'),
              Tab(text: 'Ещё нет'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildList(_status?['in_office'] as List? ?? []),
                  _buildList(_status?['left'] as List? ?? []),
                  _buildList(_status?['not_arrived'] as List? ?? [], isNotArrived: true),
                ],
              ),
      ),
    );
  }

  Widget _buildList(List items, {bool isNotArrived = false}) {
    if (items.isEmpty) {
      return const Center(child: Text('Никого нет'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isNotArrived ? Colors.grey.shade200 : AppColors.primary.withOpacity(0.1),
              child: Text(item['name'][0], style: TextStyle(color: isNotArrived ? Colors.grey : AppColors.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: isNotArrived 
                ? const Text('Ожидается') 
                : Text('Приход: ${item['check_in_time'] ?? '--:--'}${item['check_out_time'] != null ? ' | Уход: ${item['check_out_time']}' : ''}'),
            trailing: isNotArrived 
                ? null 
                : Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: item['check_out_time'] == null ? Colors.green : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

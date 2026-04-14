import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class AdminNetworksScreen extends ConsumerStatefulWidget {
  const AdminNetworksScreen({super.key});

  @override
  ConsumerState<AdminNetworksScreen> createState() =>
      _AdminNetworksScreenState();
}

class _AdminNetworksScreenState extends ConsumerState<AdminNetworksScreen> {
  List<Map<String, dynamic>> _networks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final nets = await ref.read(apiServiceProvider).getOfficeNetworks();
      if (!mounted) return;
      setState(() {
        _networks = nets;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Офисные сети')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _networks.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              size: 48, color: AppColors.textHint),
                          SizedBox(height: 12),
                          Text(
                            'Нет офисных сетей',
                            style: TextStyle(
                                color: AppColors.textHint, fontFamily: 'Inter'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _networks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final net = _networks[i];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(Icons.wifi_rounded,
                                    color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      net['name']?.toString() ??
                                          net['ip_range']?.toString() ??
                                          'Сеть',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                    Text(
                                      net['ip_range']?.toString() ??
                                          net['subnet']?.toString() ??
                                          '—',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textHint,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.error, size: 20),
                                onPressed: () =>
                                    _confirmDelete(net['id']?.toString() ?? ''),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить сеть'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сеть?',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        content: const Text('Это действие нельзя отменить.',
            style: TextStyle(fontFamily: 'Inter')),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(apiServiceProvider).dio.delete('/office-networks/$id');
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    }
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить сеть',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Название *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(
                  labelText: 'IP / подсеть *',
                  hintText: '192.168.1.0/24 или 10.0.0.1'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration:
                  const InputDecoration(labelText: 'Описание'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || ipCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Заполните обязательные поля'),
                  backgroundColor: AppColors.error,
                ));
                return;
              }
              try {
                await ref.read(apiServiceProvider).createNetwork({
                  'name': nameCtrl.text.trim(),
                  'ip_range': ipCtrl.text.trim(),
                  if (descCtrl.text.isNotEmpty)
                    'description': descCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Ошибка: $e'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}

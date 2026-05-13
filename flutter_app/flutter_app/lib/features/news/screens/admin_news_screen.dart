// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/news_model.dart';
import '../../../providers.dart';
import '../../../core/theme/app_theme.dart';

class AdminNewsScreen extends ConsumerStatefulWidget {
  const AdminNewsScreen({super.key});

  @override
  ConsumerState<AdminNewsScreen> createState() => _AdminNewsScreenState();
}

class _AdminNewsScreenState extends ConsumerState<AdminNewsScreen> {
  List<News> _news = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(apiServiceProvider).getNews();
      if (mounted) setState(() => _news = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showNewsDialog({News? existing}) async {
    final titleCtrl =
        TextEditingController(text: existing?.title ?? '');
    final contentCtrl =
        TextEditingController(text: existing?.content ?? '');
    bool pinned = existing?.pinned ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null ? 'Новая новость' : 'Редактировать новость',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontFamily: 'Inter'),
          ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Заголовок *',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Текст новости *',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: pinned,
                      onChanged: (v) => setS(() => pinned = v ?? false),
                    ),
                    const Text(
                      'Закрепить новость',
                      style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.push_pin_rounded,
                        size: 16, color: AppColors.warning),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty ||
                    contentCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Заполните заголовок и текст'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                try {
                  if (existing == null) {
                    await ref.read(apiServiceProvider).createNews(
                          title: titleCtrl.text.trim(),
                          content: contentCtrl.text.trim(),
                          pinned: pinned,
                        );
                  } else {
                    await ref.read(apiServiceProvider).updateNews(existing.id, {
                      'title': titleCtrl.text.trim(),
                      'content': contentCtrl.text.trim(),
                      'pinned': pinned,
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: Text(existing == null ? 'Опубликовать' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }

  Future<void> _delete(News news) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить новость?',
            style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        content: Text(
          '"${news.title}"\n\nЭто действие необратимо.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(apiServiceProvider).deleteNews(news.id);
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Ошибка: $e'),
                backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _togglePin(News news) async {
    try {
      await ref.read(apiServiceProvider).toggleNewsPin(news.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ошибка: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _showStats(News news) async {
    try {
      final stats = await ref.read(apiServiceProvider).getNewsStats(news.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Статистика прочтений',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontFamily: 'Inter')),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatRow('Всего сотрудников', '${stats['total_employees']}',
                  AppColors.primary),
              const SizedBox(height: 8),
              _StatRow('Прочитали', '${stats['read_count']}',
                  AppColors.success),
              const SizedBox(height: 8),
              _StatRow('Не прочитали', '${stats['unread_count']}',
                  AppColors.warning),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ошибка: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Управление новостями'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : _news.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _news.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) => _NewsAdminCard(
                      news: _news[i],
                      onEdit: () => _showNewsDialog(existing: _news[i]),
                      onDelete: () => _delete(_news[i]),
                      onPin: () => _togglePin(_news[i]),
                      onStats: () => _showStats(_news[i]),
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewsDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новая новость',
            style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
                color: AppColors.primaryLight, shape: BoxShape.circle),
            child: const Icon(Icons.article_outlined,
                size: 36, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('Новостей нет',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter')),
          const SizedBox(height: 8),
          const Text('Нажмите «Новая новость» чтобы создать',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                  fontFamily: 'Inter')),
        ],
      ),
    );
  }
}

// ─── News admin card ──────────────────────────────────────────────────────────

class _NewsAdminCard extends StatelessWidget {
  final News news;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onStats;

  const _NewsAdminCard({
    required this.news,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onStats,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('d MMM yyyy', 'ru').format(news.createdAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: news.pinned ? const Color(0xFFFFFBEB) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: news.pinned ? AppColors.warning : AppColors.border,
          width: news.pinned ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (news.pinned) ...[
                const Icon(Icons.push_pin_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  news.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onEdit();
                      break;
                    case 'pin':
                      onPin();
                      break;
                    case 'stats':
                      onStats();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textHint, size: 20),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_rounded,
                          size: 18, color: AppColors.primary),
                      SizedBox(width: 10),
                      Text('Редактировать'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(children: [
                      Icon(
                        news.pinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin_rounded,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Text(news.pinned ? 'Открепить' : 'Закрепить'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'stats',
                    child: Row(children: [
                      Icon(Icons.bar_chart_rounded,
                          size: 18, color: AppColors.success),
                      SizedBox(width: 10),
                      Text('Статистика'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppColors.error),
                      SizedBox(width: 10),
                      Text('Удалить',
                          style: TextStyle(color: AppColors.error)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            news.content,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Row ─────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontFamily: 'Inter')),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }
}

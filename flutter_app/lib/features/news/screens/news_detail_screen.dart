// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/news_model.dart';
import '../../../providers.dart';
import '../../../core/theme/app_theme.dart';

class NewsDetailScreen extends ConsumerStatefulWidget {
  final String newsId;
  const NewsDetailScreen({super.key, required this.newsId});

  @override
  ConsumerState<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends ConsumerState<NewsDetailScreen> {
  News? _news;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiServiceProvider);
      final news = await api.getNewsById(widget.newsId);
      if (mounted) setState(() { _news = news; _loading = false; });
      // Отмечаем как прочитанное (тихо, не блокируем UI)
      try { await api.markNewsRead(widget.newsId); } catch (_) {}
    } catch (e) {
      if (mounted) setState(() { _error = 'Не удалось загрузить новость'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final news = _news!;
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 0,
          floating: true,
          snap: true,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Новость'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Метаданные
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: const Text(
                        'Новость',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('d MMMM yyyy', 'ru').format(news.createdAt),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Заголовок
                Text(news.title, style: AppTextStyles.displayMedium),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),
                // Изображение (если есть)
                if (news.imageUrl != null && news.imageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      news.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                // Текст
                Text(
                  news.content,
                  style: AppTextStyles.bodyLarge.copyWith(height: 1.7),
                ),
                const SizedBox(height: 16),
                // Метка прочитано
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Отмечено как прочитанное',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class AdminQrScreen extends ConsumerStatefulWidget {
  const AdminQrScreen({super.key});

  @override
  ConsumerState<AdminQrScreen> createState() => _AdminQrScreenState();
}

class _AdminQrScreenState extends ConsumerState<AdminQrScreen> {
  Map<String, dynamic>? _qrData;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ref.read(apiServiceProvider).getCurrentQR();
      if (!mounted) return;
      setState(() {
        _qrData = data;
        _loading = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.statusCode == 404
          ? 'Активного QR ещё нет — сгенерируйте новый ниже.'
          : (e.message ?? 'Не удалось загрузить QR');
      setState(() {
        _qrData = null;
        _loading = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrData = null;
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final data = await ref.read(apiServiceProvider).generateQR();
      if (!mounted) return;
      setState(() {
        _qrData = data;
        _generating = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Новый QR-код сгенерирован'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget? _qrImageWidget() {
    final b64 = _qrData?['image_base64']?.toString();
    if (b64 == null || b64.isEmpty) return null;
    try {
      final bytes = base64Decode(b64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          bytes,
          width: 220,
          height: 220,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrBitmap = _qrImageWidget();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('QR-коды')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: AppColors.warning, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          if (qrBitmap != null) ...[
                            qrBitmap,
                            const SizedBox(height: 16),
                          ] else ...[
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.qr_code_2_rounded,
                                color: AppColors.primary,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            _qrData != null ? 'QR активен' : 'QR не найден',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontFamily: 'Inter',
                            ),
                          ),
                          if (_qrData != null) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                final token =
                                    _qrData!['token']?.toString() ?? '';
                                Clipboard.setData(ClipboardData(text: token));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Токен скопирован'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.divider,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _qrData!['token']?.toString() ?? '—',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                          fontFamily: 'Inter',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.copy_rounded,
                                        size: 14,
                                        color: AppColors.textHint),
                                  ],
                                ),
                              ),
                            ),
                            if (_qrData!['type'] != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Тип: ${_qrData!['type']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                            if (_qrData!['expires_at'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Истекает: ${_qrData!['expires_at']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: AppColors.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'При регенерации QR все сотрудники должны использовать новый код для входа/выхода и завершения дежурства.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.warning,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _generating ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_generating
                            ? 'Генерация...'
                            : 'Сгенерировать новый QR'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

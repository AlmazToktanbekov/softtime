import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class DailyReportsScreen extends ConsumerStatefulWidget {
  const DailyReportsScreen({super.key});

  @override
  ConsumerState<DailyReportsScreen> createState() => _DailyReportsScreenState();
}

class _DailyReportsScreenState extends ConsumerState<DailyReportsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // Re-using apiService via DIO directly for the new endpoint
      // Or create a method in api_service.dart, but we can just use dio:
      final dio = ref.read(apiServiceProvider).dio;
      final res = await dio.get('/attendance/daily-reports?report_date=$date');
      setState(() {
        _reports = List<Map<String, dynamic>>.from(res.data);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Дневные отчёты (сегодня)', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _reports.isEmpty
                  ? const Center(child: Text('Никто ещё не писал отчёты', style: TextStyle(color: AppColors.textHint)))
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reports.length,
                        itemBuilder: (context, i) {
                          final r = _reports[i];
                          String name = r['employee_name'] ?? '';
                          if (name.isEmpty) name = 'Сотрудник';
                          final checkIn = r['formatted_check_in'];
                          final checkOut = r['formatted_check_out'];
                          final report = r['daily_report'] ?? 'Ещё не ушел(а) или не написал(а) отчёт';
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppColors.primaryLight,
                                      foregroundColor: AppColors.primary,
                                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter', fontSize: 15)),
                                          const SizedBox(height: 2),
                                          Text('Приход: ${checkIn ?? '-'} • Уход: ${checkOut ?? '-'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(report, style: const TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

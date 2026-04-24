import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class RoomBookingScreen extends ConsumerStatefulWidget {
  const RoomBookingScreen({super.key});

  @override
  ConsumerState<RoomBookingScreen> createState() => _RoomBookingScreenState();
}

class _RoomBookingScreenState extends ConsumerState<RoomBookingScreen> {
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _bookings = [];
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String get _dateStr {
    final d = _selectedDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService().getRooms(),
        ApiService().getRoomBookings(date: _dateStr),
      ]);
      setState(() {
        _rooms = results[0] as List<Map<String, dynamic>>;
        _bookings = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('🏢 Переговорки', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          _buildDatePicker(),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else if (_rooms.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🏢', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text('Переговорок нет', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Попросите администратора добавить комнаты', style: TextStyle(color: AppColors.textHint)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rooms.length,
                  itemBuilder: (ctx, i) => _RoomSection(
                    room: _rooms[i],
                    bookings: _bookings.where((b) => b['room_id'] == _rooms[i]['id']).toList(),
                    onBook: () => _showBookingDialog(_rooms[i]),
                    onDelete: _loadData,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    final days = List.generate(7, (i) => DateTime.now().add(Duration(days: i)));
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 70,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: days.length,
          itemBuilder: (ctx, i) {
            final day = days[i];
            final isSelected = day.day == _selectedDate.day && day.month == _selectedDate.month;
            final dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
            return GestureDetector(
              onTap: () {
                setState(() => _selectedDate = day);
                _loadData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                width: 52,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.divider,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayNames[day.weekday - 1],
                      style: TextStyle(
                        color: isSelected ? Colors.white70 : AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showBookingDialog(Map<String, dynamic> room) {
    final titleCtrl = TextEditingController();
    String startTime = '09:00';
    String endTime = '10:00';

    final times = [
      '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
      '12:00', '12:30', '13:00', '13:30', '14:00', '14:30', '15:00', '15:30',
      '16:00', '16:30', '17:00', '17:30', '18:00',
    ];

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🏢 Бронь: ${room['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(_dateStr, style: TextStyle(color: AppColors.textHint)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Тема встречи *'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('С:', style: TextStyle(fontWeight: FontWeight.w600)),
                        DropdownButton<String>(
                          value: startTime,
                          isExpanded: true,
                          items: times.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setModal(() => startTime = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('По:', style: TextStyle(fontWeight: FontWeight.w600)),
                        DropdownButton<String>(
                          value: endTime,
                          isExpanded: true,
                          items: times.where((t) => t.compareTo(startTime) > 0).map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setModal(() => endTime = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    try {
                      await ApiService().createRoomBooking({
                        'room_id': room['id'],
                        'title': titleCtrl.text.trim(),
                        'booking_date': _dateStr,
                        'start_time': startTime,
                        'end_time': endTime,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadData();
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
                        );
                      }
                    }
                  },
                  child: const Text('Забронировать', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomSection extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> bookings;
  final VoidCallback onBook;
  final VoidCallback onDelete;

  const _RoomSection({required this.room, required this.bookings, required this.onBook, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Room header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('🏢', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('до ${room['capacity'] ?? 0} человек', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: onBook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('+ Забронировать', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
          if (bookings.isNotEmpty) ...[
            Divider(color: AppColors.divider, height: 1),
            ...bookings.map((b) => ListTile(
              leading: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${b['start_time']}-${b['end_time']}',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
              title: Text(b['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(b['user_name'] ?? '', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.error,
                onPressed: () async {
                  try {
                    await ApiService().deleteRoomBooking(b['id']);
                    onDelete();
                  } catch (_) {}
                },
              ),
            )),
          ] else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('Нет броней на этот день', style: TextStyle(color: AppColors.textHint)),
              ),
            ),
        ],
      ),
    );
  }
}

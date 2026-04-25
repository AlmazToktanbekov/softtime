import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class RoomBookingScreen extends StatefulWidget {
  const RoomBookingScreen({super.key});

  @override
  State<RoomBookingScreen> createState() => _RoomBookingScreenState();
}

class _RoomBookingScreenState extends State<RoomBookingScreen> {
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _bookings = [];
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final results = await Future.wait([
        ApiService().getRooms(),
        ApiService().getRoomBookings(date: dateStr),
      ]);
      setState(() {
        _rooms = results[0] as List<Map<String, dynamic>>;
        _bookings = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('🗓 Бронь переговорок', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
      ),
      body: Column(
        children: [
          _buildDatePicker(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rooms.isEmpty
                    ? const Center(child: Text('Комнат пока нет'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rooms.length,
                        itemBuilder: (ctx, i) => _RoomCard(
                          room: _rooms[i],
                          bookings: _bookings.where((b) => b['room_id'] == _rooms[i]['id']).toList(),
                          onBook: _showBookingDialog,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
              _loadData();
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: () {
              setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
              _loadData();
            },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _showBookingDialog(Map<String, dynamic> room) {
    final titleCtrl = TextEditingController();
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Бронь: ${room['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Цель встречи')),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('С'),
                      subtitle: Text(startTime.format(ctx)),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: startTime);
                        if (t != null) setModalState(() => startTime = t);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: const Text('До'),
                      subtitle: Text(endTime.format(ctx)),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: endTime);
                        if (t != null) setModalState(() => endTime = t);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty) return;
                    try {
                      final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
                      await ApiService().createRoomBooking({
                        'room_id': room['id'],
                        'title': titleCtrl.text,
                        'booking_date': dateStr,
                        'start_time': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                        'end_time': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadData();
                    } catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Конфликт времени!')));
                    }
                  },
                  child: const Text('Забронировать', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> bookings;
  final Function(Map<String, dynamic>) onBook;
  const _RoomCard({required this.room, required this.bookings, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(room['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('Вместимость: ${room['capacity']} чел.'),
            trailing: ElevatedButton(
              onPressed: () => onBook(room),
              child: const Text('Забронировать'),
            ),
          ),
          if (bookings.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider()),
            ...bookings.map((b) => ListTile(
              dense: true,
              leading: const Icon(Icons.access_time, size: 18),
              title: Text('${b['start_time']} - ${b['end_time']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(b['title'] ?? ''),
              trailing: Text(b['user_name'] ?? '', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
            )),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class EmployeeScheduleModel {
  final String id;
  final String userId;
  final int dayOfWeek;
  final bool isWorkday;
  final String? startTime;
  final String? endTime;

  EmployeeScheduleModel({
    required this.id,
    required this.userId,
    required this.dayOfWeek,
    required this.isWorkday,
    this.startTime,
    this.endTime,
  });

  factory EmployeeScheduleModel.fromJson(Map<String, dynamic> json) {
    return EmployeeScheduleModel(
      id: json['id'].toString(),
      userId: (json['user_id'] ?? json['employee_id']).toString(),
      dayOfWeek: json['day_of_week'] as int,
      isWorkday: (json['is_working_day'] ?? json['is_workday'] ?? false) as bool,
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
    );
  }

  // Геттер для обратной совместимости и schedule_screen
  bool get isWorkingDay => isWorkday;

  /// Длительность рабочего дня в минутах (0 если выходной или нет времён)
  int get durationMinutes {
    if (!isWorkday || startTime == null || endTime == null) return 0;
    final start = _parseTime(startTime!);
    final end = _parseTime(endTime!);
    if (start == null || end == null) return 0;
    final diff = end.inMinutes - start.inMinutes;
    return diff > 0 ? diff : 0;
  }

  /// HH:MM → Duration
  static Duration? _parseTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return Duration(hours: h, minutes: m);
  }

  String? get formattedStart => startTime != null ? _fmt(startTime!) : null;
  String? get formattedEnd => endTime != null ? _fmt(endTime!) : null;

  static String _fmt(String t) {
    // Берём только HH:MM (отбрасываем секунды если есть)
    final parts = t.split(':');
    if (parts.length < 2) return t;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'day_of_week': dayOfWeek,
        'is_working_day': isWorkday,
        'start_time': startTime,
        'end_time': endTime,
      };
}

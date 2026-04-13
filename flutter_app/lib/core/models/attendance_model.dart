class AttendanceModel {
  final String id;
  final String userId;
  final String date;
  final String? checkInTime;
  final String? checkOutTime;
  final String status;
  final int lateMinutes;
  final bool qrVerifiedIn;
  final bool qrVerifiedOut;
  final String? note;

  AttendanceModel({
    required this.id,
    required this.userId,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    required this.lateMinutes,
    required this.qrVerifiedIn,
    required this.qrVerifiedOut,
    this.note,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json) => AttendanceModel(
        id: json['id'].toString(),
        userId: (json['user_id'] ?? json['employee_id']).toString(),
        date: json['date'].toString(),
        checkInTime: json['check_in_time']?.toString(),
        checkOutTime: json['check_out_time']?.toString(),
        status: json['status'].toString(),
        lateMinutes: (json['late_minutes'] is int) ? json['late_minutes'] as int : int.tryParse('${json['late_minutes']}') ?? 0,
        qrVerifiedIn: json['qr_verified_in'] as bool? ?? false,
        qrVerifiedOut: json['qr_verified_out'] as bool? ?? false,
        note: json['note']?.toString(),
      );

  String get formattedCheckIn {
    if (checkInTime == null) return '--:--';
    final dt = DateTime.parse(checkInTime!).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedCheckOut {
    if (checkOutTime == null) return '--:--';
    final dt = DateTime.parse(checkOutTime!).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String? get workDuration {
    if (checkInTime == null || checkOutTime == null) return null;
    final inDt = DateTime.parse(checkInTime!);
    final outDt = DateTime.parse(checkOutTime!);
    final diff = outDt.difference(inDt);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    return '$hoursч $minutesм';
  }
}

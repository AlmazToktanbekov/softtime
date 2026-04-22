class AttendanceModel {
  final String id;
  final String userId;
  final String? employeeName;
  final String date;
  final String? checkInTime;
  final String? checkOutTime;
  final String status;
  final int lateMinutes;
  final int earlyArrivalMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final bool qrVerifiedIn;
  final bool qrVerifiedOut;
  final String? note;

  AttendanceModel({
    required this.id,
    required this.userId,
    this.employeeName,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    required this.lateMinutes,
    required this.earlyArrivalMinutes,
    required this.earlyLeaveMinutes,
    required this.overtimeMinutes,
    required this.qrVerifiedIn,
    required this.qrVerifiedOut,
    this.note,
  });

  static int _parseInt(dynamic v) =>
      (v is int) ? v : int.tryParse('$v') ?? 0;

  factory AttendanceModel.fromJson(Map<String, dynamic> json) => AttendanceModel(
        id: json['id'].toString(),
        userId: (json['user_id'] ?? json['employee_id']).toString(),
        employeeName: json['employee_name']?.toString(),
        date: json['date'].toString(),
        checkInTime: json['check_in_time']?.toString(),
        checkOutTime: json['check_out_time']?.toString(),
        status: json['status'].toString(),
        lateMinutes: _parseInt(json['late_minutes']),
        earlyArrivalMinutes: _parseInt(json['early_arrival_minutes']),
        earlyLeaveMinutes: _parseInt(json['early_leave_minutes']),
        overtimeMinutes: _parseInt(json['overtime_minutes']),
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

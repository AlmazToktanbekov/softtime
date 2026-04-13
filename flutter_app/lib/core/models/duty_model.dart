class DutyQueueItem {
  final String userId;
  final int queueOrder;

  DutyQueueItem({required this.userId, required this.queueOrder});

  factory DutyQueueItem.fromJson(Map<String, dynamic> json) => DutyQueueItem(
        userId: json['user_id'].toString(),
        queueOrder: json['queue_order'] as int,
      );
}

class DutyAssignment {
  final String id;
  final String userId;
  final String? userFullName;
  final String date;
  final String dutyType; // 'LUNCH' | 'CLEANING'
  final bool isCompleted;
  final List<dynamic>? completionTasks;
  final bool completionQrVerified;
  final String? completedAt;
  final bool verified;
  final String? verifiedBy;
  final String? verifiedAt;
  final String? adminNote;
  final String createdAt;

  DutyAssignment({
    required this.id,
    required this.userId,
    this.userFullName,
    required this.date,
    this.dutyType = 'LUNCH',
    required this.isCompleted,
    this.completionTasks,
    required this.completionQrVerified,
    this.completedAt,
    required this.verified,
    this.verifiedBy,
    this.verifiedAt,
    this.adminNote,
    required this.createdAt,
  });

  factory DutyAssignment.fromJson(Map<String, dynamic> json) {
    return DutyAssignment(
      id: json['id'].toString(),
      userId: (json['user_id'] ?? json['employee_id']).toString(),
      userFullName: json['user_full_name']?.toString(),
      date: json['date'].toString(),
      dutyType: json['duty_type']?.toString() ?? 'LUNCH',
      isCompleted: json['is_completed'] as bool,
      completionTasks: json['completion_tasks'] as List<dynamic>?,
      completionQrVerified: json['completion_qr_verified'] as bool,
      completedAt: json['completed_at']?.toString(),
      verified: json['verified'] as bool,
      verifiedBy: json['verified_by']?.toString(),
      verifiedAt: json['verified_at']?.toString(),
      adminNote: json['admin_note']?.toString(),
      createdAt: json['created_at'].toString(),
    );
  }

  bool get isLunch => dutyType == 'LUNCH';
  bool get isCleaning => dutyType == 'CLEANING';

  String get typeLabel => isLunch ? 'Обед' : 'Уборка';

  String get typeEmoji => isLunch ? '🍽️' : '🧹';
}

class DutyChecklistItem {
  final String id;
  final String text;
  final int order;
  final bool isActive;
  final String? dutyType; // null = shared, 'LUNCH' or 'CLEANING'
  final String createdAt;

  DutyChecklistItem({
    required this.id,
    required this.text,
    required this.order,
    required this.isActive,
    this.dutyType,
    required this.createdAt,
  });

  factory DutyChecklistItem.fromJson(Map<String, dynamic> json) => DutyChecklistItem(
        id: json['id'].toString(),
        text: json['text'] as String,
        order: json['order'] as int,
        isActive: json['is_active'] as bool,
        dutyType: json['duty_type']?.toString(),
        createdAt: json['created_at'].toString(),
      );
}

class DutySwap {
  final String id;
  final String requesterId;
  final String? requesterName;
  final String targetId;
  final String? targetName;
  final String assignmentId;
  final String? targetAssignmentId;
  final String? dutyType;
  final String? dutyDate;
  final String? targetPeerDate;
  final String status;
  final String? responseNote;
  final String? respondedBy;
  final String? respondedAt;
  final String createdAt;

  DutySwap({
    required this.id,
    required this.requesterId,
    this.requesterName,
    required this.targetId,
    this.targetName,
    required this.assignmentId,
    this.targetAssignmentId,
    this.dutyType,
    this.dutyDate,
    this.targetPeerDate,
    required this.status,
    this.responseNote,
    this.respondedBy,
    this.respondedAt,
    required this.createdAt,
  });

  factory DutySwap.fromJson(Map<String, dynamic> json) => DutySwap(
        id: json['id'].toString(),
        requesterId: json['requester_id'].toString(),
        requesterName: json['requester_name']?.toString(),
        targetId: json['target_id'].toString(),
        targetName: json['target_name']?.toString(),
        assignmentId: json['assignment_id'].toString(),
        targetAssignmentId: json['target_assignment_id']?.toString(),
        dutyType: json['duty_type']?.toString(),
        dutyDate: json['duty_date']?.toString(),
        targetPeerDate: json['target_peer_date']?.toString(),
        status: json['status'] as String,
        responseNote: json['response_note']?.toString(),
        respondedBy: json['responded_by']?.toString(),
        respondedAt: json['responded_at']?.toString(),
        createdAt: json['created_at'].toString(),
      );

  String get dutyTypeLabel {
    if (dutyType == 'LUNCH') return 'Обед';
    if (dutyType == 'CLEANING') return 'Уборка';
    return 'Дежурство';
  }
}

// Duty overview entry (for admin panel)
class DutyOverviewEntry {
  final String date;
  final String dutyType;
  final String? userId;
  final String? userFullName;
  final bool isCompleted;
  final bool verified;

  DutyOverviewEntry({
    required this.date,
    required this.dutyType,
    this.userId,
    this.userFullName,
    required this.isCompleted,
    required this.verified,
  });

  factory DutyOverviewEntry.fromJson(Map<String, dynamic> json) => DutyOverviewEntry(
        date: json['date'].toString(),
        dutyType: json['duty_type'].toString(),
        userId: json['user_id']?.toString(),
        userFullName: json['user_full_name']?.toString(),
        isCompleted: json['is_completed'] as bool,
        verified: json['verified'] as bool,
      );

  String get typeLabel => dutyType == 'LUNCH' ? 'Обед' : 'Уборка';
}

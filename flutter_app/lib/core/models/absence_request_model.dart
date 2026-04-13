class AbsenceRequestModel {
  final String id;
  final String userId;
  final String requestType;
  final String startDate;
  final String? endDate;
  final String? startTime;
  final String? commentEmployee;
  final String? commentAdmin;
  final String status;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? createdAt;

  AbsenceRequestModel({
    required this.id,
    required this.userId,
    required this.requestType,
    required this.startDate,
    this.endDate,
    this.startTime,
    this.commentEmployee,
    this.commentAdmin,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
  });

  factory AbsenceRequestModel.fromJson(Map<String, dynamic> json) {
    return AbsenceRequestModel(
      id: json['id'].toString(),
      userId: (json['user_id'] ?? json['employee_id']).toString(),
      requestType: json['request_type'].toString(),
      startDate: json['start_date'].toString(),
      endDate: json['end_date']?.toString(),
      startTime: json['start_time']?.toString(),
      commentEmployee: json['comment_employee']?.toString(),
      commentAdmin: json['comment_admin']?.toString(),
      status: json['status'].toString(),
      reviewedBy: json['reviewed_by']?.toString(),
      reviewedAt: json['reviewed_at']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

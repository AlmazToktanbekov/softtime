class AbsenceRequestModel {
  final int id;
  final int employeeId;
  final String requestType;
  final String startDate;
  final String? endDate;
  final String? startTime;
  final String? commentEmployee;
  final String? commentAdmin;
  final String status;
  final int? reviewedBy;
  final String? reviewedAt;
  final String? createdAt;

  AbsenceRequestModel({
    required this.id,
    required this.employeeId,
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
      id: json['id'],
      employeeId: json['employee_id'],
      requestType: json['request_type'],
      startDate: json['start_date'],
      endDate: json['end_date'],
      startTime: json['start_time'],
      commentEmployee: json['comment_employee'],
      commentAdmin: json['comment_admin'],
      status: json['status'],
      reviewedBy: json['reviewed_by'],
      reviewedAt: json['reviewed_at'],
      createdAt: json['created_at'],
    );
  }
}


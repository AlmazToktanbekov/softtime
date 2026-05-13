import 'package:intl/intl.dart';

class Task {
  final String id;
  final String title;
  final String? description;
  final String assignerId;
  final String assigneeId;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? blockerReason;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.assignerId,
    required this.assigneeId,
    required this.status,
    required this.priority,
    this.dueDate,
    this.completedAt,
    this.blockerReason,
    required this.createdAt,
    this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'].toString(),
        title: json['title'] as String,
        description: json['description']?.toString(),
        assignerId: json['assigner_id'].toString(),
        assigneeId: json['assignee_id'].toString(),
        status: json['status'].toString(),
        priority: json['priority'].toString(),
        dueDate: json['due_date'] != null ? DateFormat('yyyy-MM-dd').parse(json['due_date'].toString()) : null,
        completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'].toString()) : null,
        blockerReason: json['blocker_reason']?.toString(),
        createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
        updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      );
}

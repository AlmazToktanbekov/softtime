class UserModel {
  final int id;
  final String username;
  final String email;
  final String role;
  final int? employeeId;
  final bool isActive;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.employeeId,
    required this.isActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'],
    username: json['username'],
    email: json['email'],
    role: json['role'],
    employeeId: json['employee_id'],
    isActive: json['is_active'],
  );
}

class EmployeeModel {
  final int id;
  final String fullName;
  final String email;
  final String? phone;
  final String? department;
  final String? position;
  final String? hireDate;
  final bool isActive;

  EmployeeModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.department,
    this.position,
    this.hireDate,
    required this.isActive,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
    id: json['id'],
    fullName: json['full_name'],
    email: json['email'],
    phone: json['phone'],
    department: json['department'],
    position: json['position'],
    hireDate: json['hire_date'],
    isActive: json['is_active'],
  );
}

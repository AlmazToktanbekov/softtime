class UserModel {
  final String id;
  final String username;
  final String email;
  final String role;
  final String status;
  final String? phone;
  final String? fullName;
  final String? teamName;
  final String? teamId;
  final String? mentorId;
  final String? avatarUrl;
  final String? hiredAt;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.status,
    this.phone,
    this.fullName,
    this.teamName,
    this.teamId,
    this.mentorId,
    this.avatarUrl,
    this.hiredAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'].toString(),
        username: json['username'] as String,
        email: json['email'] as String,
        role: json['role'].toString(),
        status: json['status'].toString(),
        phone: json['phone']?.toString(),
        fullName: json['full_name']?.toString(),
        teamName: json['team_name']?.toString(),
        teamId: json['team_id']?.toString(),
        mentorId: json['mentor_id']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
        hiredAt: json['hired_at']?.toString(),
      );

  bool get isAdmin => role == 'ADMIN' || role == 'SUPER_ADMIN';
  bool get isTeamLead => role == 'TEAM_LEAD';
  bool get isIntern => role == 'INTERN';

  String get displayRole {
    switch (role) {
      case 'SUPER_ADMIN':
        return 'Супер Админ';
      case 'ADMIN':
        return 'Администратор';
      case 'TEAM_LEAD':
        return 'Ментор';
      case 'EMPLOYEE':
        return 'Сотрудник';
      case 'INTERN':
        return 'Стажёр';
      default:
        return role;
    }
  }
}

class EmployeeModel {
  final String id;
  final String fullName;
  final String username;
  final String email;
  final String? phone;
  final String? teamName;
  final String? teamId;
  final String? mentorId;
  final String? avatarUrl;
  final String? hireDate;
  final String status;
  final String role;

  EmployeeModel({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    this.phone,
    this.teamName,
    this.teamId,
    this.mentorId,
    this.avatarUrl,
    this.hireDate,
    required this.status,
    this.role = 'EMPLOYEE',
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
        id: json['id'].toString(),
        fullName: json['full_name'] as String,
        username: json['username'] as String? ?? '',
        email: json['email'] as String,
        phone: json['phone']?.toString(),
        teamName: json['team_name']?.toString(),
        teamId: json['team_id']?.toString(),
        mentorId: json['mentor_id']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
        hireDate: json['hired_at']?.toString(),
        status: json['status'].toString(),
        role: json['role']?.toString() ?? 'EMPLOYEE',
      );

  bool get isActiveUser => status == 'ACTIVE';

  String get displayRole {
    switch (role) {
      case 'SUPER_ADMIN':
        return 'Супер Админ';
      case 'ADMIN':
        return 'Администратор';
      case 'TEAM_LEAD':
        return 'Ментор';
      case 'EMPLOYEE':
        return 'Сотрудник';
      case 'INTERN':
        return 'Стажёр';
      default:
        return role;
    }
  }
}

// ── Team model ─────────────────────────────────────────────────────────────────

class TeamMember {
  final String id;
  final String fullName;
  final String role;
  final String status;
  final String? avatarUrl;

  TeamMember({
    required this.id,
    required this.fullName,
    required this.role,
    required this.status,
    this.avatarUrl,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        id: json['id'].toString(),
        fullName: json['full_name'] as String,
        role: json['role'].toString(),
        status: json['status'].toString(),
        avatarUrl: json['avatar_url']?.toString(),
      );
}

class TeamModel {
  final String id;
  final String name;
  final String? description;
  final String? mentorId;
  final String? mentorName;
  final int memberCount;
  final List<TeamMember> members;

  TeamModel({
    required this.id,
    required this.name,
    this.description,
    this.mentorId,
    this.mentorName,
    this.memberCount = 0,
    this.members = const [],
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) => TeamModel(
        id: json['id'].toString(),
        name: json['name'] as String,
        description: json['description']?.toString(),
        mentorId: json['mentor_id']?.toString(),
        mentorName: json['mentor_name']?.toString(),
        memberCount: json['member_count'] as int? ?? 0,
        members: (json['members'] as List<dynamic>?)
                ?.map((m) => TeamMember.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

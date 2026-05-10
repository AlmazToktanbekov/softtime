import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';

class AuthState {
  final UserModel? user;
  final EmployeeModel? employee;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.employee, this.isLoading = false, this.error});

  AuthState copyWith({UserModel? user, EmployeeModel? employee, bool? isLoading, String? error}) {
    return AuthState(
      user: user ?? this.user,
      employee: employee ?? this.employee,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get isAuthenticated => user != null;
  bool get isAdmin => user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN';
  bool get isTeamlead => user?.role == 'TEAM_LEAD';
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState());

  Future<bool> init() async {
    try {
      if (!await _api.isLoggedIn()) return false;
      final user = await _api.getMe();
      EmployeeModel? emp;
      try {
        emp = await _api.getEmployee(user.id);
      } catch (_) {}
      state = state.copyWith(user: user, employee: emp);
      
      // Update FCM token on startup if already logged in
      FcmService.updateToken();
      
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<(UserModel, EmployeeModel?)> _fetchUserAndEmployee() async {
    final user = await _api.getMe();
    EmployeeModel? emp;
    try {
      emp = await _api.getEmployee(user.id);
    } catch (_) {}
    return (user, emp);
  }

  Future<String?> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.login(username, password);
      final (user, emp) = await _fetchUserAndEmployee();
      state = state.copyWith(user: user, employee: emp, isLoading: false);
      
      // Update FCM token after successful login
      FcmService.updateToken();
      
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String? detail;
      if (data is Map && data['detail'] is String) {
        detail = data['detail'] as String;
      }

      final msg = status == 401
          ? 'Неверный логин или пароль'
          : (detail ??
              (e.type == DioExceptionType.connectionTimeout ||
                      e.type == DioExceptionType.receiveTimeout ||
                      e.type == DioExceptionType.sendTimeout
                  ? 'Сервер не отвечает. Проверьте подключение к Wi‑Fi.'
                  : 'Ошибка входа'));
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    } on Exception catch (_) {
      const msg = 'Ошибка подключения. Проверьте интернет.';
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }
  }

  Future<void> refreshUser() async {
    try {
      final (user, emp) = await _fetchUserAndEmployee();
      state = state.copyWith(user: user, employee: emp);
    } catch (_) {}
  }

  void updateAvatarUrl(String avatarUrl) {
    final user = state.user;
    if (user == null) return;
    final updatedUser = UserModel(
      id: user.id,
      username: user.username,
      email: user.email,
      role: user.role,
      status: user.status,
      phone: user.phone,
      fullName: user.fullName,
      teamName: user.teamName,
      teamId: user.teamId,
      mentorId: user.mentorId,
      avatarUrl: avatarUrl,
      hiredAt: user.hiredAt,
    );
    final emp = state.employee;
    final updatedEmp = emp == null
        ? null
        : EmployeeModel(
            id: emp.id,
            fullName: emp.fullName,
            username: emp.username,
            email: emp.email,
            phone: emp.phone,
            teamName: emp.teamName,
            teamId: emp.teamId,
            mentorId: emp.mentorId,
            avatarUrl: avatarUrl,
            hireDate: emp.hireDate,
            status: emp.status,
            role: emp.role,
          );
    state = AuthState(
      user: updatedUser,
      employee: updatedEmp,
      isLoading: state.isLoading,
      error: state.error,
    );
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ApiService());
});

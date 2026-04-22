import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

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
    if (!await _api.isLoggedIn()) return false;
    try {
      final user = await _api.getMe();
      EmployeeModel? emp;
      try {
        emp = await _api.getEmployee(user.id);
      } catch (_) {}
      state = state.copyWith(user: user, employee: emp);
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

  Future<void> logout() async {
    await _api.logout();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ApiService());
});

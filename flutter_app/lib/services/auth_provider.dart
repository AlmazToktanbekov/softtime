import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool get isAdmin => user?.role == 'admin';
  bool get isManager => user?.role == 'manager';
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState());

  Future<bool> init() async {
    if (!await _api.isLoggedIn()) return false;
    try {
      final user = await _api.getMe();
      EmployeeModel? emp;
      if (user.employeeId != null) {
        emp = await _api.getEmployee(user.employeeId!);
      }
      state = state.copyWith(user: user, employee: emp);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.login(username, password);
      final user = await _api.getMe();
      EmployeeModel? emp;
      if (user.employeeId != null) {
        emp = await _api.getEmployee(user.employeeId!);
      }
      state = state.copyWith(user: user, employee: emp, isLoading: false);
      return null;
    } on Exception catch (e) {
      final msg = e.toString().contains('401')
          ? 'Неверный логин или пароль'
          : 'Ошибка подключения. Проверьте интернет.';
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AuthState();
  }
}

final apiServiceProvider = Provider((ref) => ApiService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(apiServiceProvider));
});

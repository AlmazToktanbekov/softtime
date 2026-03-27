import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../models/absence_request_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
    receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
  ))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try refresh
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await _dio.fetch(error.requestOptions);
            handler.resolve(response);
            return;
          }
        }
        handler.next(error);
      },
    ));

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;
      final response = await Dio().post(
        '${AppConfig.baseUrl}/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      await _storage.write(key: 'access_token', value: response.data['access_token']);
      await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  // AUTH
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    await _storage.write(key: 'access_token', value: response.data['access_token']);
    await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
    return response.data;
  }

  Future<UserModel> getMe() async {
    final response = await _dio.get('/auth/me');
    return UserModel.fromJson(response.data);
  }

  Future<void> logout() async {
    try { await _dio.post('/auth/logout'); } catch (_) {}
    await _storage.deleteAll();
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  // EMPLOYEE
  Future<EmployeeModel> getEmployee(int id) async {
    final response = await _dio.get('/employees/$id');
    return EmployeeModel.fromJson(response.data);
  }

  Future<List<EmployeeModel>> getEmployees() async {
    final response = await _dio.get('/employees');
    return (response.data as List).map((e) => EmployeeModel.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) async {
    final response = await _dio.post('/employees', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateEmployee(int id, Map<String, dynamic> data) async {
    final response = await _dio.put('/employees/$id', data: data);
    return response.data;
  }

  Future<void> deactivateEmployee(int id) async {
    await _dio.patch('/employees/$id/deactivate');
  }

  // ATTENDANCE
  Future<AttendanceModel> checkIn(String qrToken) async {
    final response = await _dio.post('/attendance/check-in', data: {
      'qr_token': qrToken,
      'device_info': 'Flutter App',
    });
    return AttendanceModel.fromJson(response.data);
  }

  Future<AttendanceModel> checkOut(String qrToken) async {
    final response = await _dio.post('/attendance/check-out', data: {
      'qr_token': qrToken,
      'device_info': 'Flutter App',
    });
    return AttendanceModel.fromJson(response.data);
  }

  Future<List<AttendanceModel>> getMyAttendance({String? startDate, String? endDate}) async {
    final response = await _dio.get('/attendance/my', queryParameters: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });
    return (response.data as List).map((e) => AttendanceModel.fromJson(e)).toList();
  }

  Future<List<AttendanceModel>> getAllAttendance({
    String? startDate, String? endDate, int? employeeId, String? department
  }) async {
    final response = await _dio.get('/attendance', queryParameters: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (employeeId != null) 'employee_id': employeeId,
      if (department != null) 'department': department,
    });
    return (response.data as List).map((e) => AttendanceModel.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> manualUpdate(int id, Map<String, dynamic> data) async {
    final response = await _dio.patch('/attendance/$id/manual-update', data: data);
    return response.data;
  }

  /// Админ: отметить разрешённое отсутствие (сотрудник не пришёл по уважительной причине).
  Future<AttendanceModel> markApprovedAbsence({
    required int employeeId,
    required String date,
    required String note,
  }) async {
    final response = await _dio.post('/attendance/mark-approved-absence', data: {
      'employee_id': employeeId,
      'date': date,
      'note': note,
    });
    return AttendanceModel.fromJson(response.data);
  }

  // QR
  Future<Map<String, dynamic>> getCurrentQR() async {
    final response = await _dio.get('/qr/current');
    return response.data;
  }

  Future<Map<String, dynamic>> generateQR() async {
    final response = await _dio.post('/qr/generate');
    return response.data;
  }

  // OFFICE NETWORKS
  Future<List<Map<String, dynamic>>> getOfficeNetworks() async {
    final response = await _dio.get('/office-networks');
    return List<Map<String, dynamic>>.from(response.data);
  }

  Future<Map<String, dynamic>> createNetwork(Map<String, dynamic> data) async {
    final response = await _dio.post('/office-networks', data: data);
    return response.data;
  }

  // REPORTS
  Future<Map<String, dynamic>> getDailyReport(String date) async {
    final response = await _dio.get('/reports/daily', queryParameters: {'report_date': date});
    return response.data;
  }

  Future<Map<String, dynamic>> getWeeklyReport() async {
    final response = await _dio.get('/reports/weekly');
    return response.data;
  }

  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    final response = await _dio.get('/reports/monthly', queryParameters: {
      'year': year, 'month': month
    });
    return response.data;
  }

  // ABSENCE REQUESTS
  Future<AbsenceRequestModel> createAbsenceRequest({
    required String requestType,
    required String startDate,
    String? endDate,
    String? startTime,
    String? commentEmployee,
  }) async {
    final response = await _dio.post('/absence-requests', data: {
      'request_type': requestType,
      'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (startTime != null) 'start_time': startTime,
      if (commentEmployee != null && commentEmployee.isNotEmpty)
        'comment_employee': commentEmployee,
    });
    return AbsenceRequestModel.fromJson(response.data);
  }

  Future<List<AbsenceRequestModel>> getMyAbsenceRequests() async {
    final response = await _dio.get('/absence-requests/my');
    return (response.data as List)
        .map((e) => AbsenceRequestModel.fromJson(e))
        .toList();
  }

  Future<List<AbsenceRequestModel>> getAbsenceRequests({
    String? status,
    int? employeeId,
    String? requestType,
  }) async {
    final response = await _dio.get('/absence-requests', queryParameters: {
      if (status != null) 'status': status,
      if (employeeId != null) 'employee_id': employeeId,
      if (requestType != null) 'request_type': requestType,
    });
    return (response.data as List)
        .map((e) => AbsenceRequestModel.fromJson(e))
        .toList();
  }

  Future<AbsenceRequestModel> reviewAbsenceRequest({
    required int requestId,
    required String status,
    String? commentAdmin,
  }) async {
    final response = await _dio.patch('/absence-requests/$requestId/review', data: {
      'status': status,
      if (commentAdmin != null && commentAdmin.isNotEmpty) 'comment_admin': commentAdmin,
    });
    return AbsenceRequestModel.fromJson(response.data);
  }
}

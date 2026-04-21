import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../models/absence_request_model.dart';
import '../models/duty_model.dart';
import '../models/news_model.dart';
import '../models/task_model.dart';
import '../models/employee_schedule_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  static const String _baseUrlStorageKey = 'api_base_url';
  late String _baseUrl = AppConfig.baseUrl;
  Dio? _dio;
  bool _refreshing = false;

  Future<void> init() async {
    final saved = await _storage.read(key: _baseUrlStorageKey);
    final isLocalhost = saved != null &&
        (saved.contains('127.0.0.1') ||
            saved.contains('localhost') ||
            saved.contains('10.0.2.2'));
    if (saved != null && saved.trim().isNotEmpty && !isLocalhost) {
      _baseUrl = _normalizeBaseUrl(saved);
    } else {
      _baseUrl = _normalizeBaseUrl(AppConfig.baseUrl);
      await _storage.write(key: _baseUrlStorageKey, value: _baseUrl);
    }
    _dio = _buildDio(_baseUrl);
  }

  /// Полный URL для /uploads/... с сервера
  String mediaAbsoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    var root = _baseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
    if (path.startsWith('/')) return '$root$path';
    return '$root/$path';
  }

  String get baseUrl => _baseUrl;

  Future<void> setBaseUrl(String url) async {
    final normalized = _normalizeBaseUrl(url);
    _baseUrl = normalized;
    await _storage.write(key: _baseUrlStorageKey, value: normalized);
    _dio = _buildDio(_baseUrl);
  }

  Dio get dio {
    _dio ??= _buildDio(_baseUrl);
    return _dio!;
  }

  String _normalizeBaseUrl(String url) {
    var u = url.trim();
    // Убираем trailing slashes
    u = u.replaceAll(RegExp(r'/+$'), '');
    // Убираем /api/v1, /api/v1/, /api если пользователь добавил лишнее
    u = u.replaceAll(RegExp(r'/api/v1$'), '');
    u = u.replaceAll(RegExp(r'/api$'), '');
    // Добавляем правильный суффикс
    u = '$u/api/v1';
    return u;
  }

  Dio _buildDio(String baseUrl) {
    final d = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
    ));

    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final refreshed = await _refreshToken();
            if (refreshed) {
              final token = await _storage.read(key: 'access_token');
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              final response = await d.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            }
          }
          handler.next(error);
        },
      ),
    );

    return d;
  }

  Future<bool> _refreshToken() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) {
        await _clearTokens();
        return false;
      }
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
      )).post(
        '$_baseUrl/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      await _storage.write(key: 'access_token', value: response.data['access_token']);
      await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
      return true;
    } catch (_) {
      await _clearTokens();
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // AUTH
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    await _storage.write(key: 'access_token', value: response.data['access_token']);
    await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
    return response.data;
  }

  /// Регистрация заявки на доступ к системе (статус pending),
  /// окончательное подтверждение делает администратор.
  /// Список менторов для регистрации стажёра (без токена).
  Future<List<Map<String, dynamic>>> fetchRegisterMentors() async {
    final r = await Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
    )).get('$_baseUrl/auth/register/mentors');
    return List<Map<String, dynamic>>.from(r.data as List);
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String username,
    required String password,
    String? phone,
    String? role,
    String? mentorId,
  }) async {
    final response = await dio.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'username': username,
      'password': password,
      if (phone != null) 'phone': phone,
      if (role != null) 'role': role,
      if (mentorId != null) 'mentor_id': mentorId,
    });
    return response.data;
  }

  Future<UserModel> getMe() async {
    final response = await dio.get('/auth/me');
    return UserModel.fromJson(response.data);
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    await _storage.deleteAll();
    _refreshing = false;
    try {
      if (refreshToken != null) {
        await Dio(BaseOptions(
          connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
          receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
        )).post('$_baseUrl/auth/logout', data: {'refresh_token': refreshToken});
      }
    } catch (_) {}
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  /// Сохранить FCM токен на сервере для получения push-уведомлений.
  Future<void> updateFcmToken(String fcmToken) async {
    try {
      await dio.post('/auth/fcm-token', data: {'fcm_token': fcmToken});
    } catch (_) {
      // не блокируем запуск приложения при ошибке
    }
  }

  // EMPLOYEE (все вызовы идут на /users — единый роутер backend)
  Future<EmployeeModel> getEmployee(String id) async {
    final response = await dio.get('/users/$id');
    return EmployeeModel.fromJson(response.data);
  }

  Future<List<EmployeeModel>> getEmployees() async {
    final response = await dio.get('/users');
    final data = response.data;
    // Backend возвращает PaginatedUsers { items: [...], total, page, limit }
    final list = data is Map ? (data['items'] as List? ?? []) : (data as List);
    return list.map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) async {
    final response = await dio.post('/users', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateEmployee(String id, Map<String, dynamic> data) async {
    final response = await dio.put('/users/$id', data: data);
    return response.data;
  }

  Future<void> deactivateEmployee(String id) async {
    await dio.patch('/users/$id/deactivate');
  }

  // EMPLOYEE SCHEDULES
  Future<List<EmployeeScheduleModel>> getEmployeeSchedules(String employeeId) async {
    final response = await dio.get('/employee-schedules/employee/$employeeId');
    return (response.data as List)
        .map((e) => EmployeeScheduleModel.fromJson(e))
        .toList();
  }

  // ATTENDANCE
  Future<AttendanceModel> checkIn(String qrToken) async {
    final response = await dio.post('/attendance/check-in', data: {
      'qr_token': qrToken,
      'device_info': 'Flutter App',
    });
    return AttendanceModel.fromJson(response.data);
  }

  Future<AttendanceModel> checkOut(String qrToken) async {
    final response = await dio.post('/attendance/check-out', data: {
      'qr_token': qrToken,
      'device_info': 'Flutter App',
    });
    return AttendanceModel.fromJson(response.data);
  }

  Future<List<AttendanceModel>> getMyAttendance({String? startDate, String? endDate}) async {
    final response = await dio.get('/attendance/my', queryParameters: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });
    return (response.data as List).map((e) => AttendanceModel.fromJson(e)).toList();
  }

  Future<List<AttendanceModel>> getAllAttendance({
    String? startDate, String? endDate, String? userId, String? department
  }) async {
    final response = await dio.get('/attendance', queryParameters: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (userId != null) 'user_id': userId,
      if (department != null) 'department': department,
    });
    return (response.data as List).map((e) => AttendanceModel.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> manualUpdate(String id, Map<String, dynamic> data) async {
    final response = await dio.patch('/attendance/$id/manual-update', data: data);
    return response.data;
  }

  /// Админ: отметить разрешённое отсутствие (сотрудник не пришёл по уважительной причине).
  Future<AttendanceModel> markApprovedAbsence({
    required String userId,
    required String date,
    required String note,
  }) async {
    final response = await dio.post('/attendance/approved-absence', data: {
      'user_id': userId,
      'date': date,
      'note': note,
    });
    return AttendanceModel.fromJson(response.data);
  }

  // QR
  Future<Map<String, dynamic>> getCurrentQR() async {
    final response = await dio.get('/qr/current');
    return response.data;
  }

  Future<Map<String, dynamic>> generateQR() async {
    final response = await dio.post('/qr/generate');
    return response.data;
  }

  // OFFICE NETWORKS
  Future<List<Map<String, dynamic>>> getOfficeNetworks() async {
    final response = await dio.get('/office-networks');
    return List<Map<String, dynamic>>.from(response.data);
  }

  Future<Map<String, dynamic>> createNetwork(Map<String, dynamic> data) async {
    final response = await dio.post('/office-networks', data: data);
    return response.data;
  }

  // REPORTS
  Future<Map<String, dynamic>> getDailyReport(String date) async {
    final response = await dio.get('/reports/daily', queryParameters: {'report_date': date});
    return response.data;
  }

  Future<Map<String, dynamic>> getWeeklyReport({String? weekStart}) async {
    final params = weekStart != null ? {'week_start': weekStart} : null;
    final response = await dio.get('/reports/weekly', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    final response = await dio.get('/reports/monthly', queryParameters: {
      'year': year, 'month': month
    });
    return response.data;
  }

  Future<Map<String, dynamic>> getEmployeeReport(
    String userId, {
    String? startDate,
    String? endDate,
  }) async {
    final params = <String, dynamic>{};
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;
    final response = await dio.get('/reports/employee/$userId',
        queryParameters: params.isEmpty ? null : params);
    return response.data;
  }

  // DUTY
  /// Дежурные сегодня — возвращает список (LUNCH + CLEANING).
  Future<List<DutyAssignment>> getTodayDuties() async {
    final response = await dio.get('/duty/today');
    if (response.data == null) return [];
    return (response.data as List).map((e) => DutyAssignment.fromJson(e)).toList();
  }

  /// Обратная совместимость: первый дежурный сегодня (LUNCH).
  Future<DutyAssignment?> getTodayDuty() async {
    final list = await getTodayDuties();
    try {
      return list.firstWhere((d) => d.isLunch);
    } catch (_) {
      return list.isNotEmpty ? list.first : null;
    }
  }

  Future<List<DutyAssignment>> getMyDutyAssignments({String? dutyType}) async {
    final response = await dio.get('/duty/my', queryParameters: {
      if (dutyType != null) 'duty_type': dutyType,
    });
    return (response.data as List).map((e) => DutyAssignment.fromJson(e)).toList();
  }

  Future<List<DutySwap>> getIncomingSwaps() async {
    final response = await dio.get('/duty/swaps/incoming');
    return (response.data as List).map((e) => DutySwap.fromJson(e)).toList();
  }

  Future<List<DutySwap>> getMySwaps() async {
    final response = await dio.get('/duty/swaps/my');
    return (response.data as List).map((e) => DutySwap.fromJson(e)).toList();
  }

  Future<String?> acceptSwap(String swapId) async {
    final response = await dio.patch('/duty/swap/$swapId/accept');
    final data = response.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    return null;
  }

  Future<void> rejectSwap(String swapId, {String? note}) async {
    await dio.patch('/duty/swap/$swapId/reject',
        queryParameters: note != null ? {'note': note} : null);
  }

  Future<void> requestSwap({
    required String assignmentId,
    required String targetUserId,
    String? targetAssignmentId,
  }) async {
    await dio.post('/duty/swap-request', data: {
      'assignment_id': assignmentId,
      'target_user_id': targetUserId,
      if (targetAssignmentId != null) 'target_assignment_id': targetAssignmentId,
    });
  }

  Future<List<Map<String, dynamic>>> getDutyColleagues() async {
    final response = await dio.get('/duty/colleagues');
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<DutyAssignment>> getPeerDutyAssignments(String userId, {String? fromDate}) async {
    final response = await dio.get(
      '/duty/peer/$userId/assignments',
      queryParameters: {if (fromDate != null) 'from_date': fromDate},
    );
    return (response.data as List).map((e) => DutyAssignment.fromJson(e)).toList();
  }

  Future<DutyAssignment> completeDuty({
    required String assignmentId,
    required List<String> taskIds,
    required String qrToken,
  }) async {
    final response = await dio.patch('/duty/$assignmentId/complete', data: {
      'tasks': taskIds,
      'qr_token': qrToken,
    });
    return DutyAssignment.fromJson(response.data);
  }

  Future<List<DutyAssignment>> getDutySchedule({
    String? startDate,
    String? endDate,
    String? dutyType,
  }) async {
    final response = await dio.get('/duty/schedule', queryParameters: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (dutyType != null) 'duty_type': dutyType,
    });
    return (response.data as List).map((e) => DutyAssignment.fromJson(e)).toList();
  }

  Future<List<DutyOverviewEntry>> getDutyOverview({
    required String startDate,
    required String endDate,
  }) async {
    final response = await dio.get('/duty/overview', queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
    });
    return (response.data as List).map((e) => DutyOverviewEntry.fromJson(e)).toList();
  }

  Future<List<DutyChecklistItem>> getDutyChecklist({String? dutyType}) async {
    final response = await dio.get('/duty/checklist', queryParameters: {
      if (dutyType != null) 'duty_type': dutyType,
    });
    return (response.data as List).map((e) => DutyChecklistItem.fromJson(e)).toList();
  }

  /// Админ/тимлид подтверждает дежурство.
  Future<void> verifyDuty(String assignmentId, bool approve, {String? adminNote}) async {
    await dio.patch('/duty/$assignmentId/verify', data: {
      'approve': approve,
      if (adminNote != null && adminNote.isNotEmpty) 'admin_note': adminNote,
    });
  }

  /// Админ вручную отмечает дежурство как выполненное (без QR).
  Future<void> completeDutyManual(String assignmentId) async {
    await dio.patch('/duty/$assignmentId/complete-manual');
  }

  // NEWS
  Future<List<News>> getNews() async {
    final response = await dio.get('/news');
    return (response.data as List).map((e) => News.fromJson(e)).toList();
  }

  Future<News> getNewsById(String newsId) async {
    final response = await dio.get('/news/$newsId');
    return News.fromJson(response.data);
  }

  Future<void> markNewsRead(String newsId) async {
    await dio.post('/news/$newsId/read');
  }

  // TASKS
  Future<List<Task>> getTasks() async {
    final response = await dio.get('/tasks');
    return (response.data as List).map((e) => Task.fromJson(e)).toList();
  }

  Future<Task> updateTask(String taskId, {required String status}) async {
    final response = await dio.patch('/tasks/$taskId', data: {'status': status});
    return Task.fromJson(response.data);
  }

  Future<Task> createTask({
    required String title,
    required String assigneeId,
    required String priority,
    String? description,
    String? dueDate, // yyyy-mm-dd
  }) async {
    final response = await dio.post('/tasks', data: {
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      'assignee_id': assigneeId,
      'priority': priority,
      if (dueDate != null) 'due_date': dueDate,
    });
    return Task.fromJson(response.data);
  }

  // NEWS — ADMIN
  Future<News> createNews({
    required String title,
    required String content,
    bool pinned = false,
    String type = 'general',
  }) async {
    final response = await dio.post('/news', data: {
      'title': title,
      'content': content,
      'pinned': pinned,
      'type': type,
      'target_audience': 'all',
    });
    return News.fromJson(response.data);
  }

  Future<News> updateNews(String newsId, Map<String, dynamic> data) async {
    final response = await dio.put('/news/$newsId', data: data);
    return News.fromJson(response.data);
  }

  Future<void> deleteNews(String newsId) async {
    await dio.delete('/news/$newsId');
  }

  Future<void> toggleNewsPin(String newsId) async {
    await dio.patch('/news/$newsId/pin');
  }

  Future<Map<String, dynamic>> getNewsStats(String newsId) async {
    final response = await dio.get('/news/$newsId/stats');
    return response.data;
  }

  // DUTY — ADMIN
  Future<DutyAssignment> assignDuty({
    required String userId,
    required String date,
    String dutyType = 'LUNCH',
  }) async {
    final response = await dio.post('/duty/assign', data: {
      'user_id': userId,
      'date': date,
      'duty_type': dutyType,
    });
    return DutyAssignment.fromJson(response.data);
  }

  /// Назначить обед на всю неделю.
  Future<List<DutyAssignment>> assignWeeklyLunch({
    required String weekStart,
    required List<Map<String, dynamic>> entries,
  }) async {
    final response = await dio.post('/duty/assign/weekly-lunch', data: {
      'week_start': weekStart,
      'entries': entries,
    });
    return (response.data as List).map((e) => DutyAssignment.fromJson(e)).toList();
  }

  Future<void> deleteAssignment(String assignmentId) async {
    await dio.delete('/duty/assign/$assignmentId');
  }

  Future<List<DutyAssignment>> getDutyScheduleAll({
    String? startDate,
    String? endDate,
    String? dutyType,
  }) async {
    final response = await dio.get('/duty/schedule', queryParameters: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (dutyType != null) 'duty_type': dutyType,
    });
    return (response.data as List)
        .map((e) => DutyAssignment.fromJson(e))
        .toList();
  }

  // TEAMS
  Future<List<TeamModel>> getTeams() async {
    final response = await dio.get('/teams');
    return (response.data as List).map((e) => TeamModel.fromJson(e)).toList();
  }

  Future<TeamModel> getTeam(String teamId) async {
    final response = await dio.get('/teams/$teamId');
    return TeamModel.fromJson(response.data);
  }

  Future<TeamModel> getMyTeam() async {
    final response = await dio.get('/teams/my/team');
    return TeamModel.fromJson(response.data);
  }

  Future<TeamModel> createTeam({
    required String name,
    String? description,
    String? mentorId,
  }) async {
    final response = await dio.post('/teams', data: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      if (mentorId != null) 'mentor_id': mentorId,
    });
    return TeamModel.fromJson(response.data);
  }

  Future<TeamModel> updateTeam(String teamId, {
    String? name,
    String? description,
    String? mentorId,
  }) async {
    final response = await dio.put('/teams/$teamId', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (mentorId != null) 'mentor_id': mentorId,
    });
    return TeamModel.fromJson(response.data);
  }

  Future<TeamModel> assignTeamMembers(String teamId, List<String> userIds) async {
    final response = await dio.post('/teams/$teamId/members', data: {
      'user_ids': userIds,
    });
    return TeamModel.fromJson(response.data);
  }

  Future<void> deleteTeam(String teamId) async {
    await dio.delete('/teams/$teamId');
  }

  // AVATAR UPLOAD
  Future<String> uploadAvatar(File imageFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });
    final response = await dio.patch('/users/me/avatar', data: formData);
    return response.data['avatar_url'] as String;
  }

  /// Upload avatar using a one-time token (e.g. upload_token from /register).
  Future<String> uploadAvatarWithToken(File imageFile, String token) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });
    final d = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
      headers: {'Authorization': 'Bearer $token'},
    ));
    final response = await d.patch('/users/me/avatar', data: formData);
    return response.data['avatar_url'] as String;
  }

  // EMPLOYEE SCHEDULES — ADMIN
  Future<void> saveScheduleDay({
    required String userId,
    required int dayOfWeek,
    required bool isWorkday,
    String? startTime,
    String? endTime,
  }) async {
    await dio.post('/employee-schedules/user/$userId', data: {
      'day_of_week': dayOfWeek,
      'is_working_day': isWorkday,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
    });
  }

  // ABSENCE REQUESTS
  Future<AbsenceRequestModel> createAbsenceRequest({
    required String requestType,
    required String startDate,
    String? endDate,
    String? startTime,
    String? commentEmployee,
  }) async {
    final response = await dio.post('/absence-requests', data: {
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
    final response = await dio.get('/absence-requests/my');
    return (response.data as List)
        .map((e) => AbsenceRequestModel.fromJson(e))
        .toList();
  }

  Future<List<AbsenceRequestModel>> getAbsenceRequests({
    String? status,
    String? userId,
    String? requestType,
  }) async {
    final response = await dio.get('/absence-requests', queryParameters: {
      if (status != null) 'status': status,
      if (userId != null) 'user_id': userId,
      if (requestType != null) 'request_type': requestType,
    });
    return (response.data as List)
        .map((e) => AbsenceRequestModel.fromJson(e))
        .toList();
  }

  Future<AbsenceRequestModel> reviewAbsenceRequest({
    required String requestId,
    required String status,
    String? commentAdmin,
  }) async {
    final response = await dio.patch('/absence-requests/$requestId/review', data: {
      'status': status,
      if (commentAdmin != null && commentAdmin.isNotEmpty) 'comment_admin': commentAdmin,
    });
    return AbsenceRequestModel.fromJson(response.data);
  }

  Future<Map<String, dynamic>> getTodayOfficeStatus() async {
    final response = await dio.get('/attendance/today-status');
    return response.data as Map<String, dynamic>;
  }
}

// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _done = false;

  /// EMPLOYEE | INTERN | TEAM_LEAD (ментор)
  String _selectedRole = 'EMPLOYEE';
  File? _avatarFile;

  List<Map<String, dynamic>> _mentors = [];
  bool _mentorsLoading = false;
  String? _selectedMentorId;

  @override
  void initState() {
    super.initState();
    _loadMentors();
  }

  Future<void> _loadMentors() async {
    setState(() => _mentorsLoading = true);
    try {
      final list = await ApiService().fetchRegisterMentors();
      if (mounted) setState(() => _mentors = list);
    } catch (_) {
      if (mounted) setState(() => _mentors = []);
    } finally {
      if (mounted) setState(() => _mentorsLoading = false);
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _avatarFile = File(picked.path));
    }
  }

  Future<void> _editServer() async {
    final api = ApiService();
    final ctrl = TextEditingController(text: api.baseUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Адрес сервера'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(hintText: 'http://192.168.1.1:8000'),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (newUrl == null || !mounted) return;
    await api.setBaseUrl(newUrl);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Сервер: ${api.baseUrl}'),
        backgroundColor: AppColors.success,
      ));
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    if (_avatarFile == null) {
      setState(() => _error = 'Добавьте фото профиля');
      return;
    }
    if (_selectedRole == 'INTERN') {
      if (_selectedMentorId == null || _selectedMentorId!.isEmpty) {
        setState(() => _error = 'Выберите ментора из списка');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService();

      // Phone: user inputs digits after +996, we send +996XXXXXXXXX
      final phone = '+996${_phoneCtrl.text.trim()}';

      // 1. Register — response includes upload_token for avatar
      final regResult = await api.register(
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        phone: phone,
        role: _selectedRole,
        mentorId: _selectedRole == 'INTERN' ? _selectedMentorId : null,
      );

      // 2. Upload avatar using the one-time token (no login needed)
      final uploadToken = regResult['upload_token'] as String?;
      if (uploadToken != null && _avatarFile != null) {
        try {
          await api.uploadAvatarWithToken(_avatarFile!, uploadToken);
        } catch (_) {
          // Avatar upload failed — not critical, continue
        }
      }

      if (mounted)
        setState(() {
          _done = true;
          _loading = false;
        });
    } on DioException catch (e) {
      // Network / no response
      if (e.response == null) {
        final hint = ApiService().baseUrl;
        if (mounted) {
          setState(() {
            _error =
                'Нет подключения к серверу.\nПроверьте адрес сервера и что backend запущен и доступен.\nСейчас: $hint';
            _loading = false;
          });
        }
        return;
      }

      final data = e.response?.data;
      String detail = 'Ошибка регистрации';
      if (data is Map && data['detail'] is String) {
        detail = data['detail'] as String;
      } else if (data is Map && data['detail'] is List) {
        // FastAPI validation errors: [{"loc":[...], "msg":"...", ...}, ...]
        try {
          final first = (data['detail'] as List).cast<dynamic>().first;
          if (first is Map && first['msg'] is String)
            detail = first['msg'] as String;
        } catch (_) {}
      }
      if (mounted)
        setState(() {
          _error = detail;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'Ошибка подключения';
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Создать аккаунт'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_ethernet_rounded, size: 20),
            tooltip: 'Адрес сервера',
            onPressed: _editServer,
          ),
        ],
      ),
      body: _done ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top_rounded,
                  size: 48, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            const Text(
              'Заявка отправлена!',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Администратор рассмотрит вашу заявку.\n\nПосле подтверждения вы сможете войти в приложение.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Понятно'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Фото профиля ────────────────────────────────────────────────
            _sectionLabel('Фото профиля'),
            const SizedBox(height: 12),
            Center(child: _buildAvatarPicker()),
            const SizedBox(height: 24),

            // ── Кто вы? ─────────────────────────────────────────────────────
            _sectionLabel('Кто вы?'),
            const SizedBox(height: 12),
            _buildRoleSelector(),
            const SizedBox(height: 16),

            // ── Команда / ментор ───────────────────────────────────────────
            _sectionLabel('Команда'),
            const SizedBox(height: 8),
            if (_selectedRole == 'INTERN') ...[
              Text(
                _mentorsLoading
                    ? 'Загрузка списка менторов…'
                    : 'Укажите вашего ментора. Состав команды закрепляет администратор.',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (!_mentorsLoading && _mentors.isEmpty)
                const Text(
                  'Нет доступных менторов. Попросите администратора активировать ментора или проверьте адрес сервера.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.warning,
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedMentorId,
                  decoration: const InputDecoration(
                    labelText: 'Ментор',
                    prefixIcon:
                        Icon(Icons.supervisor_account_outlined, size: 20),
                  ),
                  hint: const Text('Выберите ментора'),
                  items: _mentors
                      .map((m) => DropdownMenuItem<String>(
                            value: m['id']?.toString(),
                            child: Text(
                              '${m['full_name'] ?? ''} (${_mentorRoleLabel(m['role']?.toString())})',
                              style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 14),
                            ),
                          ))
                      .toList(),
                  onChanged: _mentorsLoading
                      ? null
                      : (v) => setState(() => _selectedMentorId = v),
                ),
            ] else ...[
              const Text(
                'Команду создаёт администратор: назначает ментора и участников. После подтверждения заявки вы получите доступ.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Личные данные ────────────────────────────────────────────────
            _sectionLabel('Личные данные'),
            const SizedBox(height: 12),
            _buildField(
              ctrl: _fullNameCtrl,
              label: 'ФИО полностью',
              icon: Icons.badge_outlined,
              validator: (v) => v!.trim().length < 2 ? 'Введите ФИО' : null,
            ),
            const SizedBox(height: 12),
            _buildField(
              ctrl: _emailCtrl,
              label: 'Email (Gmail)',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v!.isEmpty) return 'Введите email';
                if (!v.contains('@')) return 'Некорректный email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildPhoneField(),
            const SizedBox(height: 24),

            // ── Данные для входа ─────────────────────────────────────────────
            _sectionLabel('Данные для входа'),
            const SizedBox(height: 12),
            _buildField(
              ctrl: _usernameCtrl,
              label: 'Логин',
              icon: Icons.alternate_email_rounded,
              validator: (v) {
                if (v!.trim().isEmpty) return 'Введите логин';
                if (v.trim().length < 3) return 'Минимум 3 символа';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildField(
              ctrl: _passwordCtrl,
              label: 'Пароль',
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePass,
              suffix: IconButton(
                icon: Icon(
                  _obscurePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.textHint,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
              validator: (v) {
                if (v!.length < 4) return 'Минимум 4 символа';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildField(
              ctrl: _confirmCtrl,
              label: 'Подтвердите пароль',
              icon: Icons.lock_outline_rounded,
              obscure: _obscureConfirm,
              suffix: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.textHint,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (v) => v!.isEmpty ? 'Повторите пароль' : null,
            ),
            const SizedBox(height: 24),

            // ── Error ─────────────────────────────────────────────────────────
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            fontFamily: 'Inter')),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Зарегистрироваться'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Avatar picker ──────────────────────────────────────────────────────────

  Widget _buildAvatarPicker() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryLight,
              border: Border.all(
                color:
                    _avatarFile != null ? AppColors.primary : AppColors.border,
                width: 2.5,
              ),
              image: _avatarFile != null
                  ? DecorationImage(
                      image: FileImage(_avatarFile!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _avatarFile == null
                ? const Icon(Icons.person_rounded,
                    size: 48, color: AppColors.primary)
                : null,
          ),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt_rounded,
                size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _mentorRoleLabel(String? r) {
    switch (r) {
      case 'TEAM_LEAD':
        return 'ментор';
      case 'ADMIN':
      case 'SUPER_ADMIN':
        return 'админ';
      default:
        return r ?? '';
    }
  }

  // ── Role selector (сотрудник / стажёр / ментор) ─────────────────────────────

  Widget _buildRoleSelector() {
    Widget tile(String value, String title, String subtitle, IconData icon) {
      final selected = _selectedRole == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedRole = value;
            if (value != 'INTERN') _selectedMentorId = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    color: selected ? AppColors.primary : AppColors.textHint,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.primary, size: 22),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        tile('EMPLOYEE', 'Сотрудник', 'Обычный участник команды',
            Icons.work_outline_rounded),
        tile('INTERN', 'Стажёр', 'Работает с назначенным ментором',
            Icons.school_outlined),
        tile(
            'TEAM_LEAD',
            'Ментор',
            'Руководит группой; команду оформляет администратор',
            Icons.groups_outlined),
      ],
    );
  }

  // ── Phone field with +996 prefix ──────────────────────────────────────────

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      onChanged: (_) => setState(() {}),
      style: const TextStyle(
          fontFamily: 'Inter', fontSize: 15, color: AppColors.textPrimary),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Введите номер телефона';
        if (v.trim().length < 9) return 'Введите 9 цифр после +996';
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Телефон',
        prefixIcon: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '+996',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color.fromARGB(255, 15, 65, 130),
            ),
          ),
        ),
        hintText: '700 123 456',
      ),
    );
  }

  // ── Generic field ──────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(
          fontFamily: 'Inter', fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

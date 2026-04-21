// ignore_for_file: deprecated_member_use
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/attendance_model.dart';
import '../../../core/models/duty_model.dart';
import '../../../core/models/news_model.dart';
import '../../../core/models/employee_schedule_model.dart';
import '../../../providers.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_badge.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
const _kTeal = Color(0xFF06D6A0);
const _kOrange = Color(0xFFFF8C42);
const _kCard1 = Color.fromARGB(255, 0, 36, 199);
const _kCard2 = Color(0xFF3BC9A0);
const _kCard3 = Color(0xFFFF6B6B);
const _kBg = Color(0xFFEEF0F8);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  // ── data ──────────────────────────────────────────────────────────────────
  AttendanceModel? _today;
  List<DutyAssignment> _todayDuties = [];
  List<News> _news = [];
  List<EmployeeScheduleModel> _schedules = [];
  List<DutySwap> _incomingSwaps = [];
  Map<String, dynamic>? _officeStatus;

  bool _loadingAttendance = true;
  bool _loadingDuty = true;
  bool _loadingNews = true;
  bool _loadingSchedule = true;
  bool _loadingOffice = true;
  bool _actionLoading = false;
  String? _error;

  // ── animations ────────────────────────────────────────────────────────────
  late AnimationController _headerCtrl;
  late AnimationController _cardsCtrl;
  late AnimationController _sectionsCtrl;

  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  late Animation<double> _cardsFade;
  late Animation<Offset> _cardsSlide;

  late List<Animation<double>> _sectionFades;
  late List<Animation<Offset>> _sectionSlides;

  @override
  void initState() {
    super.initState();

    // header
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));

    // stat cards
    _cardsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _cardsFade = CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOut);
    _cardsSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOutCubic));

    // sections (staggered)
    _sectionsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));

    _sectionFades = List.generate(6, (i) {
      final start = 0.1 * i;
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _sectionsCtrl,
          curve:
              Interval(start, (start + 0.5).clamp(0, 1), curve: Curves.easeOut),
        ),
      );
    });

    _sectionSlides = List.generate(6, (i) {
      final start = 0.1 * i;
      return Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
          .animate(
        CurvedAnimation(
          parent: _sectionsCtrl,
          curve: Interval(start, (start + 0.5).clamp(0, 1),
              curve: Curves.easeOutCubic),
        ),
      );
    });

    // kick off animations
    _headerCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _cardsCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _sectionsCtrl.forward();
    });

    _loadAll();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _cardsCtrl.dispose();
    _sectionsCtrl.dispose();
    super.dispose();
  }

  // ── load ──────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    await Future.wait([
      _loadAttendance(),
      _loadDuty(),
      _loadNews(),
      _loadSchedule(),
      _loadIncomingSwaps(),
      _loadOfficeStatus(),
    ]);
  }

  Future<void> _loadOfficeStatus() async {
    if (mounted) setState(() => _loadingOffice = true);
    Map<String, dynamic>? data;
    try {
      data = await ref.read(apiServiceProvider).getTodayOfficeStatus();
    } catch (e) {
      debugPrint('loadOfficeStatus error: $e');
    }
    if (mounted)
      setState(() {
        _officeStatus = data;
        _loadingOffice = false;
      });
  }

  Future<void> _loadIncomingSwaps() async {
    try {
      final swaps = await ref.read(apiServiceProvider).getIncomingSwaps();
      if (mounted) {
        setState(() => _incomingSwaps =
            swaps.where((s) => s.status == 'pending').toList());
      }
    } catch (_) {}
  }

  Future<void> _loadAttendance() async {
    if (mounted) setState(() => _loadingAttendance = true);
    AttendanceModel? result;
    String? error;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final recs = await ref
          .read(apiServiceProvider)
          .getMyAttendance(startDate: today, endDate: today);
      result = recs.isNotEmpty ? recs.first : null;
    } catch (e) {
      error = _parseError(e);
    }
    if (mounted)
      setState(() {
        _today = result;
        _loadingAttendance = false;
        if (error != null) _error = error;
      });
  }

  Future<void> _loadDuty() async {
    if (mounted) setState(() => _loadingDuty = true);
    List<DutyAssignment> duties = [];
    try {
      duties = await ref.read(apiServiceProvider).getTodayDuties();
    } catch (_) {}
    if (mounted)
      setState(() {
        _todayDuties = duties;
        _loadingDuty = false;
      });
  }

  Future<void> _loadNews() async {
    if (mounted) setState(() => _loadingNews = true);
    List<News> news = [];
    try {
      news = (await ref.read(apiServiceProvider).getNews()).take(3).toList();
    } catch (_) {}
    if (mounted)
      setState(() {
        _news = news;
        _loadingNews = false;
      });
  }

  Future<void> _loadSchedule() async {
    if (mounted) setState(() => _loadingSchedule = true);
    List<EmployeeScheduleModel> schedules = [];
    try {
      final uid = ref.read(authProvider).user?.id;
      if (uid != null)
        schedules =
            await ref.read(apiServiceProvider).getEmployeeSchedules(uid);
    } catch (_) {}
    if (mounted)
      setState(() {
        _schedules = schedules;
        _loadingSchedule = false;
      });
  }

  Future<void> _onCheckIn() async {
    final result = await context.push<String>('/qr-scanner', extra: 'check_in');
    if (result == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      final rec = await ref.read(apiServiceProvider).checkIn(result);
      if (!mounted) return;
      setState(() {
        _today = rec;
        _actionLoading = false;
      });
      _showSnack('Приход отмечен! ✓', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      _showSnack(_parseError(e), AppColors.error);
    }
  }

  Future<void> _onCheckOut() async {
    final result =
        await context.push<String>('/qr-scanner', extra: 'check_out');
    if (result == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      final rec = await ref.read(apiServiceProvider).checkOut(result);
      if (!mounted) return;
      setState(() {
        _today = rec;
        _actionLoading = false;
      });
      _showSnack('Уход отмечен!', AppColors.primary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      _showSnack(_parseError(e), AppColors.error);
    }
  }

  String _parseError(dynamic e) {
    final s = e.toString();
    final m = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(s);
    if (m != null) return m.group(1)!;
    if (s.contains('SocketException') ||
        s.contains('refused') ||
        s.contains('timed out')) {
      return 'Нет подключения к серверу';
    }
    return 'Произошла ошибка';
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  EmployeeScheduleModel? get _todaySchedule {
    final dow = DateTime.now().weekday - 1;
    try {
      return _schedules.firstWhere((s) => s.dayOfWeek == dow);
    } catch (_) {
      return null;
    }
  }

  bool _isMyDutyToday(String? uid) =>
      uid != null && _todayDuties.any((d) => d.userId == uid && d.isLunch);

  String _liveWorkTime() {
    if (_today?.checkInTime == null) return '';
    final inDt = DateTime.parse(_today!.checkInTime!).toLocal();
    final diff = DateTime.now().difference(inDt);
    if (diff.isNegative) return '';
    final h = diff.inHours, m = diff.inMinutes % 60;
    return h > 0 ? '$h ч $m м' : '$m м';
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Доброе утро'
        : now.hour < 17
            ? 'Добрый день'
            : 'Добрый вечер';
    final firstName = user?.fullName?.split(' ').first ?? 'Сотрудник';

    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        color: AppColors.primary,
        displacement: 80,
        onRefresh: () async {
          setState(() => _error = null);
          _headerCtrl.forward(from: 0);
          _cardsCtrl.forward(from: 0);
          _sectionsCtrl.forward(from: 0);
          await _loadAll();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── HEADER ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _headerFade,
                child: SlideTransition(
                  position: _headerSlide,
                  child: _Header(
                    greeting: greeting,
                    firstName: firstName,
                    avatarUrl: ref
                        .read(apiServiceProvider)
                        .mediaAbsoluteUrl(user?.avatarUrl),
                    isAdmin: auth.isAdmin,
                    onAvatar: () => context.push('/home/profile'),
                    onAdmin: () => context.push('/home/admin'),
                    now: now,
                  ),
                ),
              ),
            ),

            // ── QUICK STAT CARDS ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _cardsFade,
                child: SlideTransition(
                  position: _cardsSlide,
                  child: _QuickStatsRow(
                    loading: _loadingOffice,
                    inOfficeCount:
                        (_officeStatus?['in_office'] as List?)?.length ?? 0,
                    dutiesCount: _todayDuties.length,
                    newsCount: _news.length,
                    onOffice: () {},
                    onDuty: () => context.go('/duty'),
                    onNews: () => context.go('/news'),
                  ),
                ),
              ),
            ),

            // ── BODY SECTIONS ────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // error banner
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _AnimatedSection(
                      fade: _sectionFades[0],
                      slide: _sectionSlides[0],
                      child: _ErrorBanner(
                        message: _error!,
                        onRetry: () {
                          setState(() => _error = null);
                          _loadAll();
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // duty callout
                  if (_isMyDutyToday(user?.id)) ...[
                    _AnimatedSection(
                      fade: _sectionFades[0],
                      slide: _sectionSlides[0],
                      child:
                          _DutyCalloutCard(onOpen: () => context.go('/duty')),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // incoming swap requests banner
                  if (_incomingSwaps.isNotEmpty) ...[
                    _AnimatedSection(
                      fade: _sectionFades[0],
                      slide: _sectionSlides[0],
                      child: _SwapRequestBanner(
                        swaps: _incomingSwaps,
                        onOpen: () async {
                          await context.push('/duty');
                          _loadIncomingSwaps();
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // attendance
                  _AnimatedSection(
                    fade: _sectionFades[1],
                    slide: _sectionSlides[1],
                    child: _AttendanceCard(
                      record: _today,
                      loading: _loadingAttendance,
                      actionLoading: _actionLoading,
                      schedule: _todaySchedule,
                      liveTime: _liveWorkTime(),
                      enableCheckInOut: !auth.isAdmin,
                      onCheckIn: _onCheckIn,
                      onCheckOut: _onCheckOut,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // office status
                  _AnimatedSection(
                    fade: _sectionFades[2],
                    slide: _sectionSlides[2],
                    child: _OfficeStatusCard(
                      data: _officeStatus,
                      loading: _loadingOffice,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // schedule mini
                  _AnimatedSection(
                    fade: _sectionFades[3],
                    slide: _sectionSlides[3],
                    child: _ScheduleMini(
                      schedules: _schedules,
                      loading: _loadingSchedule,
                      onTap: () => context.push('/home/schedule'),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // duty section
                  _AnimatedSection(
                    fade: _sectionFades[4],
                    slide: _sectionSlides[4],
                    child: _DutySectionHome(
                      duties: _todayDuties,
                      loading: _loadingDuty,
                      currentUserId: user?.id,
                      onOpen: () => context.go('/duty'),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // news mini
                  _AnimatedSection(
                    fade: _sectionFades[5],
                    slide: _sectionSlides[5],
                    child: _NewsMini(
                      news: _news,
                      loading: _loadingNews,
                      onAll: () => context.go('/news'),
                      onItem: (id) => context.push('/news/$id'),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final String greeting;
  final String firstName;
  final String avatarUrl;
  final bool isAdmin;
  final VoidCallback onAvatar;
  final VoidCallback onAdmin;
  final DateTime now;

  const _Header({
    required this.greeting,
    required this.firstName,
    required this.avatarUrl,
    required this.isAdmin,
    required this.onAvatar,
    required this.onAdmin,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.fromARGB(255, 32, 93, 247),
            Color.fromARGB(255, 0, 20, 68),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(38)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Привет, $firstName! 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    GestureDetector(
                      onTap: onAdmin,
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.admin_panel_settings_outlined,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  GestureDetector(
                    onTap: onAvatar,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 2),
                      ),
                      child: ClipOval(
                        child: avatarUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 84,
                                memCacheHeight: 84,
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                    firstName.isNotEmpty
                                        ? firstName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  firstName.isNotEmpty
                                      ? firstName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // date chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('EEEE, d MMMM', 'ru').format(now).capitalize(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QUICK STATS ROW
// ══════════════════════════════════════════════════════════════════════════════

class _QuickStatsRow extends StatelessWidget {
  final bool loading;
  final int inOfficeCount;
  final int dutiesCount;
  final int newsCount;
  final VoidCallback onOffice;
  final VoidCallback onDuty;
  final VoidCallback onNews;

  const _QuickStatsRow({
    required this.loading,
    required this.inOfficeCount,
    required this.dutiesCount,
    required this.newsCount,
    required this.onOffice,
    required this.onDuty,
    required this.onNews,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatMiniCard(
              icon: Icons.people_rounded,
              label: 'В офисе',
              value: loading ? '...' : '$inOfficeCount',
              color: const Color.fromARGB(255, 32, 93, 247),
              onTap: onOffice,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _StatMiniCard(
              icon: Icons.cleaning_services_rounded,
              label: 'Дежурство',
              value: '$dutiesCount',
              color: const Color.fromARGB(255, 32, 93, 247),
              onTap: onDuty,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatMiniCard(
              icon: Icons.article_rounded,
              label: 'Новости',
              value: '$newsCount',
              color: const Color.fromARGB(255, 32, 93, 247),
              onTap: onNews,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatMiniCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _StatMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  State<_StatMiniCard> createState() => _StatMiniCardState();
}

class _StatMiniCardState extends State<_StatMiniCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 16),
              ),
              const SizedBox(height: 10),
              Text(
                widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ANIMATED SECTION WRAPPER
// ══════════════════════════════════════════════════════════════════════════════

class _AnimatedSection extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  const _AnimatedSection({
    required this.fade,
    required this.slide,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ERROR BANNER
// ══════════════════════════════════════════════════════════════════════════════

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.error, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Повтор',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DUTY CALLOUT
// ══════════════════════════════════════════════════════════════════════════════

class _DutyCalloutCard extends StatelessWidget {
  final VoidCallback onOpen;
  const _DutyCalloutCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C42), Color(0xFFFFB347)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _kOrange.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.restaurant_menu_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Вы сегодня дежурный!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                      )),
                  SizedBox(height: 4),
                  Text('Нажмите для подробностей',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'Inter',
                      )),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SWAP REQUEST BANNER
// ══════════════════════════════════════════════════════════════════════════════

class _SwapRequestBanner extends StatelessWidget {
  final List<DutySwap> swaps;
  final VoidCallback onOpen;

  const _SwapRequestBanner({required this.swaps, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final count = swaps.length;
    final names = swaps
        .map((s) => s.requesterName ?? 'Сотрудник')
        .toSet()
        .take(2)
        .join(', ');
    final subtitle = count == 1
        ? '$names хочет поменяться с вами дежурством'
        : '$names и ещё ${count - 1} чел. хотят поменяться';

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4361EE).withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4361EE).withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4361EE).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded,
                      color: Color(0xFF4361EE), size: 24),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6B6B),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? 'Запрос на обмен дежурством'
                        : '$count запроса на обмен',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontFamily: 'Inter',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF4361EE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Смотреть',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ATTENDANCE CARD
// ══════════════════════════════════════════════════════════════════════════════

class _AttendanceCard extends StatelessWidget {
  final AttendanceModel? record;
  final bool loading;
  final bool actionLoading;
  final EmployeeScheduleModel? schedule;
  final String liveTime;
  final bool enableCheckInOut;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _AttendanceCard({
    required this.record,
    required this.loading,
    required this.actionLoading,
    required this.schedule,
    required this.liveTime,
    required this.enableCheckInOut,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  bool get _excused => record?.status.toLowerCase() == 'approved_absence';
  bool get _canIn =>
      !_excused && (record == null || record!.checkInTime == null);
  bool get _canOut =>
      !_excused && record?.checkInTime != null && record?.checkOutTime == null;
  bool get _done => record?.checkOutTime != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: loading
          ? Padding(
              padding: const EdgeInsets.all(20), child: _Shimmer(height: 120))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // header row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.access_time_rounded,
                            color: AppColors.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Посещаемость',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      if (record != null) StatusBadge(status: record!.status),
                    ],
                  ),

                  // schedule
                  if (schedule != null && schedule!.isWorkingDay) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.schedule_rounded,
                            size: 13, color: AppColors.textHint),
                        const SizedBox(width: 6),
                        Text(
                          'График: ${schedule!.formattedStart} – ${schedule!.formattedEnd}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // time boxes
                  Row(children: [
                    _TimeBox(
                      label: 'Приход',
                      value: record?.formattedCheckIn ?? '--:--',
                      icon: Icons.login_rounded,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    _TimeBox(
                      label: 'Уход',
                      value: record?.formattedCheckOut ?? '--:--',
                      icon: Icons.logout_rounded,
                      color: AppColors.error,
                    ),
                    if (liveTime.isNotEmpty ||
                        record?.workDuration != null) ...[
                      const SizedBox(width: 10),
                      _TimeBox(
                        label: _done ? 'Итого' : 'Сейчас',
                        value: _done ? (record?.workDuration ?? '') : liveTime,
                        icon: Icons.timer_outlined,
                        color: AppColors.primary,
                      ),
                    ],
                  ]),

                  // late warning
                  if (record != null && record!.lateMinutes > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 15),
                        const SizedBox(width: 8),
                        Text(
                          'Опоздание: ${record!.lateMinutes} мин',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // action area
                  if (!enableCheckInOut)
                    _InfoBox(
                      color: AppColors.primary,
                      bg: AppColors.primaryLight,
                      icon: Icons.info_outline_rounded,
                      text:
                          'Для администраторов учёт посещаемости ведётся через панель администратора.',
                    )
                  else if (_excused)
                    _InfoBox(
                      color: AppColors.success,
                      bg: AppColors.successLight,
                      icon: Icons.verified_user_rounded,
                      text:
                          'Сегодня у вас утверждённое отсутствие. Отметки не нужны.',
                    )
                  else if (actionLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2.5),
                      ),
                    )
                  else
                    _ActionButtons(
                      canCheckIn: _canIn,
                      canCheckOut: _canOut,
                      onCheckIn: onCheckIn,
                      onCheckOut: onCheckOut,
                    ),
                ],
              ),
            ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final Color color, bg;
  final IconData icon;
  final String text;

  const _InfoBox({
    required this.color,
    required this.bg,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _TimeBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFamily: 'Inter',
                    letterSpacing: -0.3)),
            const SizedBox(height: 1),
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textHint,
                    fontFamily: 'Inter')),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool canCheckIn, canCheckOut;
  final VoidCallback onCheckIn, onCheckOut;

  const _ActionButtons({
    required this.canCheckIn,
    required this.canCheckOut,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: _PressButton(
        label: 'Приход',
        icon: Icons.login_rounded,
        color: AppColors.success,
        enabled: canCheckIn,
        onTap: onCheckIn,
      )),
      const SizedBox(width: 10),
      Expanded(
          child: _PressButton(
        label: 'Уход',
        icon: Icons.logout_rounded,
        color: AppColors.error,
        enabled: canCheckOut,
        onTap: onCheckOut,
      )),
    ]);
  }
}

class _PressButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _PressButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    return GestureDetector(
      onTapDown: (_) {
        if (active) _ctrl.forward();
      },
      onTapUp: (_) {
        _ctrl.reverse();
        if (active) widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 50,
          decoration: BoxDecoration(
            color: active ? widget.color : widget.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: widget.color.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon,
                  color: active ? Colors.white : widget.color.withOpacity(0.35),
                  size: 18),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: TextStyle(
                      color: active
                          ? Colors.white
                          : widget.color.withOpacity(0.35),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFamily: 'Inter')),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DUTY SECTION HOME
// ══════════════════════════════════════════════════════════════════════════════

class _DutySectionHome extends StatelessWidget {
  final List<DutyAssignment> duties;
  final bool loading;
  final String? currentUserId;
  final VoidCallback onOpen;

  const _DutySectionHome({
    required this.duties,
    required this.loading,
    required this.currentUserId,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _CardShell(child: const _Shimmer(height: 60));
    }

    if (duties.isEmpty) {
      return _CardShell(
        onTap: onOpen,
        child: Row(children: [
          _IconBox(
              color: AppColors.primary, icon: Icons.cleaning_services_rounded),
          const SizedBox(width: 14),
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Дежурство сегодня',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontFamily: 'Inter')),
              SizedBox(height: 3),
              Text('Дежурного нет',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter')),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textHint, size: 18),
        ]),
      );
    }

    return Column(
      children: duties.asMap().entries.map((e) {
        final duty = e.value;
        final isMe = duty.userId == currentUserId;
        return Padding(
          padding: EdgeInsets.only(bottom: e.key < duties.length - 1 ? 10 : 0),
          child: _DutyCard(duty: duty, isMyDuty: isMe, onOpen: onOpen),
        );
      }).toList(),
    );
  }
}

class _DutyCard extends StatelessWidget {
  final DutyAssignment duty;
  final bool isMyDuty;
  final VoidCallback onOpen;

  const _DutyCard(
      {required this.duty, required this.isMyDuty, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final isLunch = duty.isLunch;
    final accent = isMyDuty ? _kOrange : (isLunch ? AppColors.primary : _kTeal);

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMyDuty ? _kOrange.withOpacity(0.4) : AppColors.border,
            width: isMyDuty ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          _IconBox(
              color: accent,
              icon: isLunch
                  ? Icons.lunch_dining_rounded
                  : Icons.cleaning_services_rounded),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${duty.typeEmoji} ${duty.typeLabel} сегодня',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontFamily: 'Inter')),
              const SizedBox(height: 4),
              Text(
                isMyDuty
                    ? 'Сегодня дежуришь ты!'
                    : (duty.userFullName ?? 'Сотрудник'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isMyDuty ? _kOrange : AppColors.textPrimary,
                    fontFamily: 'Inter'),
              ),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textHint, size: 18),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCHEDULE MINI
// ══════════════════════════════════════════════════════════════════════════════

class _ScheduleMini extends StatelessWidget {
  final List<EmployeeScheduleModel> schedules;
  final bool loading;
  final VoidCallback onTap;

  const _ScheduleMini({
    required this.schedules,
    required this.loading,
    required this.onTap,
  });

  static const _days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  int get _todayDow => DateTime.now().weekday - 1;

  EmployeeScheduleModel? _scheduleFor(int dow) {
    try {
      return schedules.firstWhere((s) => s.dayOfWeek == dow);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _IconBox(
                  color: const Color(0xFF7B61FF),
                  icon: Icons.calendar_month_rounded),
              const SizedBox(width: 12),
              const Text('Мой график',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter')),
              const Spacer(),
              const Text('Подробнее',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontFamily: 'Inter')),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary, size: 16),
            ]),
            const SizedBox(height: 16),
            if (loading)
              const _Shimmer(height: 56)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (dow) {
                  final isToday = dow == _todayDow;
                  final s = _scheduleFor(dow);
                  final isWorking = s?.isWorkingDay ?? false;

                  return Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isToday
                            ? _kCard1
                            : isWorking
                                ? AppColors.primaryLight
                                : const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                        boxShadow: isToday
                            ? [
                                BoxShadow(
                                    color: _kCard1.withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))
                              ]
                            : [],
                      ),
                      child: Center(
                        child: Text(_days[dow],
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                color: isToday
                                    ? Colors.white
                                    : isWorking
                                        ? AppColors.primary
                                        : AppColors.textHint)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isWorking
                          ? (s?.formattedStart?.substring(0, 5) ?? '')
                          : 'Вых',
                      style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Inter',
                          color: isWorking
                              ? AppColors.textSecondary
                              : AppColors.textHint),
                    ),
                  ]);
                }),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NEWS MINI
// ══════════════════════════════════════════════════════════════════════════════

class _NewsMini extends StatelessWidget {
  final List<News> news;
  final bool loading;
  final VoidCallback onAll;
  final void Function(String) onItem;

  const _NewsMini({
    required this.news,
    required this.loading,
    required this.onAll,
    required this.onItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              _IconBox(color: _kCard3, icon: Icons.newspaper_rounded),
              const SizedBox(width: 12),
              const Text('Новости',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter')),
              const Spacer(),
              GestureDetector(
                onTap: onAll,
                child: const Row(children: [
                  Text('Все',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontFamily: 'Inter')),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.primary, size: 16),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (loading)
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _Shimmer(height: 80))
          else if (news.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Center(
                child: Text('Нет новостей',
                    style: TextStyle(
                        color: AppColors.textHint, fontFamily: 'Inter')),
              ),
            )
          else
            ...news.asMap().entries.map((e) {
              final isLast = e.key == news.length - 1;
              return Column(
                children: [
                  _NewsItem(news: e.value, onTap: () => onItem(e.value.id)),
                  if (!isLast)
                    const Divider(
                        height: 1,
                        color: AppColors.divider,
                        indent: 20,
                        endIndent: 20),
                ],
              );
            }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _NewsItem extends StatelessWidget {
  final News news;
  final VoidCallback onTap;
  const _NewsItem({required this.news, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4361EE), Color(0xFF7B61FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.article_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(news.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(news.content,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                          height: 1.4),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('d MMM', 'ru').format(news.createdAt),
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textHint, fontFamily: 'Inter'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════════════════

class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _CardShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _IconBox({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double height;
  const _Shimmer({required this.height});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFEEEEEE),
      highlightColor: const Color(0xFFF8F8F8),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OFFICE STATUS CARD
// ══════════════════════════════════════════════════════════════════════════════

class _OfficeStatusCard extends StatefulWidget {
  final Map<String, dynamic>? data;
  final bool loading;

  const _OfficeStatusCard({required this.data, required this.loading});

  @override
  State<_OfficeStatusCard> createState() => _OfficeStatusCardState();
}

class _OfficeStatusCardState extends State<_OfficeStatusCard> {
  int _tab = 0; // 0=в офисе, 1=ушли, 2=не пришли

  @override
  Widget build(BuildContext context) {
    final inOffice =
        (widget.data?['in_office'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final left =
        (widget.data?['left'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final notArrived =
        (widget.data?['not_arrived'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final total = widget.data?['total'] as int? ?? 0;

    final tabs = [
      (
        label: 'В офисе',
        count: inOffice.length,
        color: AppColors.success,
        icon: Icons.business_rounded
      ),
      (
        label: 'Ушли',
        count: left.length,
        color: AppColors.primary,
        icon: Icons.logout_rounded
      ),
      (
        label: 'Нет',
        count: notArrived.length,
        color: AppColors.error,
        icon: Icons.person_off_rounded
      ),
    ];

    final currentList = [inOffice, left, notArrived][_tab];
    final currentColor = tabs[_tab].color;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              _IconBox(
                  color: const Color(0xFF06D6A0), icon: Icons.groups_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Сотрудники сегодня',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontFamily: 'Inter')),
                      if (total > 0)
                        Text('Всего $total сотрудников',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                                fontFamily: 'Inter')),
                    ]),
              ),
            ]),
          ),

          const SizedBox(height: 14),

          // Tab buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
                children: tabs.asMap().entries.map((e) {
              final i = e.key;
              final t = e.value;
              final active = _tab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? t.color.withOpacity(0.12)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? t.color.withOpacity(0.4)
                            : AppColors.border,
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Column(children: [
                      Text('${t.count}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: active ? t.color : AppColors.textHint,
                              fontFamily: 'Inter')),
                      const SizedBox(height: 2),
                      Text(t.label,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: active ? t.color : AppColors.textHint,
                              fontFamily: 'Inter')),
                    ]),
                  ),
                ),
              );
            }).toList()),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),

          // List
          widget.loading
              ? const Padding(
                  padding: EdgeInsets.all(20), child: _Shimmer(height: 80))
              : currentList.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text('Нет данных',
                            style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 13,
                                fontFamily: 'Inter')),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount:
                          currentList.length > 8 ? 8 : currentList.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: AppColors.divider,
                          indent: 56,
                          endIndent: 16),
                      itemBuilder: (_, i) {
                        final person = currentList[i];
                        final name = person['name'] as String? ?? '—';
                        final checkIn = person['check_in_time'] as String?;
                        final checkOut = person['check_out_time'] as String?;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: currentColor.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: currentColor,
                                      fontFamily: 'Inter'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Inter'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (checkIn != null)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.login_rounded,
                                    size: 12, color: AppColors.success),
                                const SizedBox(width: 3),
                                Text(checkIn,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.success,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600)),
                                if (checkOut != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.logout_rounded,
                                      size: 12, color: AppColors.textHint),
                                  const SizedBox(width: 3),
                                  Text(checkOut,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textHint,
                                          fontFamily: 'Inter')),
                                ],
                              ]),
                          ]),
                        );
                      },
                    ),

          if (!widget.loading && currentList.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '+ ещё ${currentList.length - 8} чел.',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontFamily: 'Inter'),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

extension _Cap on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/seat_status.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/share_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/calendar.dart';
import 'package:preconnect/pages/free_labs.dart';
import 'package:preconnect/pages/more_quick_access.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/settings.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/home_sections/exam_countdown.dart';
import 'package:preconnect/pages/home_sections/student_overview.dart';
import 'package:preconnect/pages/shared_widgets/quick_access_card.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/captive_login_store.dart';
import 'package:preconnect/tools/captive_wifi_http_service.dart';
import 'package:preconnect/tools/home_card_preferences.dart';
import 'package:preconnect/tools/holiday_status.dart';
import 'package:preconnect/tools/in_app_review_prompt.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:share_plus/share_plus.dart';

enum CaptiveWifiState { offline, validated, captive, unknown }

class CaptiveWifiStatus {
  const CaptiveWifiStatus({required this.state, required this.httpStatusCode});

  final CaptiveWifiState state;
  final int? httpStatusCode;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static final StreamController<HomeTab> _shortcutTabController =
      StreamController<HomeTab>.broadcast();
  static HomeTab? _pendingShortcutTab;

  static void requestShortcutTab(HomeTab tab) {
    _pendingShortcutTab = tab;
    _shortcutTabController.add(tab);
  }

  static HomeTab? takePendingShortcutTab() {
    final pending = _pendingShortcutTab;
    _pendingShortcutTab = null;
    return pending;
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeTab selectedTab = HomeTab.dashboard;
  StreamSubscription<HomeTab>? _shortcutTabSubscription;

  late final Map<HomeTab, WidgetBuilder> pages = {
    HomeTab.settings: (_) => const SettingsPage(),
    HomeTab.notifications: (_) => const NotificationsPage(),
    HomeTab.dashboard: (_) => _HomeDashboard(
      onNavigate: _setTab,
      onLogout: () => _confirmLogout(context),
    ),
    HomeTab.moreQuickAccess: (_) => MoreQuickAccessPage(onNavigate: _setTab),
    HomeTab.freeLabs: (_) => const FreeLabsPage(),
    HomeTab.calendar: (_) => const CalendarPage(),
    HomeTab.profile: (_) => const StudentProfile(),
    HomeTab.studentSchedule: (_) => const ClassSchedule(),
    HomeTab.examSchedule: (_) => const ExamSchedule(),
    HomeTab.seatStatus: (_) => const SeatStatusPage(),
    HomeTab.degreeProgress: (_) => const DegreeProgressPage(),
    HomeTab.alarms: (_) => const AlarmPage(),
    HomeTab.shareSchedule: (_) => const ShareSchedulePage(),
    HomeTab.scanSchedule: (_) => const ScanSchedulePage(),
    HomeTab.friendSchedule: (_) => FriendSchedulePage(onNavigate: _setTab),
    HomeTab.devs: (_) => const DevsPage(),
  };
  late final List<HomeTab> _tabOrder = HomeTab.values;
  final Set<HomeTab> _builtTabs = {HomeTab.dashboard};

  @override
  void initState() {
    super.initState();
    final pendingShortcutTab = HomePage.takePendingShortcutTab();
    if (pendingShortcutTab != null) {
      selectedTab = pendingShortcutTab;
      _builtTabs.add(pendingShortcutTab);
    }
    HomeTabRegistry.setActive(selectedTab);
    HomeTabRegistry.activeTab.addListener(_onRegistryTabChanged);
    _shortcutTabSubscription = HomePage._shortcutTabController.stream.listen((
      tab,
    ) {
      if (!mounted) return;
      _setTab(tab);
    });
  }

  @override
  void dispose() {
    _shortcutTabSubscription?.cancel();
    HomeTabRegistry.activeTab.removeListener(_onRegistryTabChanged);
    super.dispose();
  }

  void _onRegistryTabChanged() {
    if (!mounted) return;
    final requestedTab = HomeTabRegistry.activeTab.value;
    if (requestedTab == selectedTab) return;
    _setTab(requestedTab);
  }

  void _setTab(HomeTab tab) {
    if (selectedTab == tab) {
      HomeTabRegistry.setActive(tab);
      return;
    }
    final shouldJumpClass = tab == HomeTab.studentSchedule;
    final shouldJumpExam = tab == HomeTab.examSchedule;
    setState(() {
      selectedTab = tab;
    });
    HomeTabRegistry.setActive(tab);
    if (shouldJumpClass || shouldJumpExam) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedTab != tab) return;
        if (shouldJumpClass) {
          ClassSchedule.requestJump();
        } else if (shouldJumpExam) {
          ExamSchedule.requestJump();
        }
      });
    }
  }

  void _handleBack() {
    if (selectedTab == HomeTab.dashboard) return;
    if (selectedTab == HomeTab.scanSchedule ||
        selectedTab == HomeTab.shareSchedule) {
      _setTab(HomeTab.friendSchedule);
    } else {
      _setTab(HomeTab.dashboard);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: BracuPalette.card(context),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.logout, color: BracuPalette.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Confirm Sign Out?',
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Sign out will clear cached data. You can sign in again for fresh data.',
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BracuPalette.primary,
                          side: BorderSide(
                            color: BracuPalette.primary.withValues(alpha: 0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BracuPalette.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Sign Out'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldLogout == true) {
      if (!context.mounted) return;
      await AuthService().logout();
      RefreshBus.instance.notify(reason: 'auth');
      if (!context.mounted) return;
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: selectedTab == HomeTab.dashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedTab != HomeTab.dashboard) {
          if (selectedTab == HomeTab.scanSchedule ||
              selectedTab == HomeTab.shareSchedule) {
            _setTab(HomeTab.friendSchedule);
          } else {
            _setTab(HomeTab.dashboard);
          }
        }
      },
      child: Scaffold(
        body: BracuBackScope(
          canGoBack: selectedTab != HomeTab.dashboard,
          onBack: _handleBack,
          child: IndexedStack(
            index: selectedTab.index,
            children: _tabOrder.map((tab) {
              if (tab == selectedTab || _builtTabs.contains(tab)) {
                _builtTabs.add(tab);
                return pages[tab]!(context);
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({required this.onNavigate, required this.onLogout});

  final void Function(HomeTab tab) onNavigate;
  final Future<void> Function() onLogout;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> {
  static const _bgTop = Color(0xFFEAF4FF);
  static const _bgBottom = Color(0xFFF3FFF4);
  static const _primary = Color(0xFF1E6BE3);
  static const _accent = Color(0xFF22B573);

  late Future<_HomeData> _future;
  _HomeData? _latestData;
  bool _isRefreshing = false;
  CaptiveWifiStatus? _captiveStatus;
  bool _isCheckingCaptive = false;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  bool _autoOpenedWifiAssistant = false;
  bool _isOpeningWifiAssistant = false;
  bool _isAutoExtendingSession = false;
  DateTime? _lastAutoAssistantOpenAt;
  DateTime? _lastAutoSessionExtendAt;
  Timer? _captiveAutoTimer;

  static const Duration _captiveAutoPollInterval = Duration(seconds: 30);
  static const Duration _autoAssistantCooldown = Duration(seconds: 45);
  static const Duration _autoSessionExtendCooldown = Duration(seconds: 60);
  static const int _autoSessionExtendThresholdSeconds = 21600;

  @override
  void initState() {
    super.initState();
    _future = _loadData().then((data) {
      _latestData = data;
      return data;
    });
    if (AndroidNetworkAssist.isSupported) {
      _networkStatusSubscription = AndroidNetworkAssist.statusStream.listen(
        _applyAndroidNetworkStatus,
      );
      unawaited(_consumePostConnectionEvent());
      _captiveAutoTimer = Timer.periodic(_captiveAutoPollInterval, (_) {
        if (!mounted) return;
        unawaited(_refreshCaptiveStatus());
      });
    }
    unawaited(_refreshCaptiveStatus());
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    _networkStatusSubscription?.cancel();
    _captiveAutoTimer?.cancel();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.isReason('home_dashboard')) {
      return;
    }
    if (RefreshBus.instance.isReason('home_card_settings_changed')) {
      unawaited(_reloadCardVisibilityOnly());
      unawaited(_refreshCaptiveStatus());
      return;
    }
    if (RefreshBus.instance.isReason('auth')) {
      unawaited(_handleRefresh(notify: false));
    }
  }

  Future<void> _reloadCardVisibilityOnly() async {
    final visibility = await HomeCardPreferences.load();
    if (!mounted) return;
    setState(() {
      if (_latestData != null) {
        _latestData = _latestData!.copyWith(cardVisibility: visibility);
      }
    });
  }

  Future<_HomeData> _loadData({bool forceRefresh = false}) async {
    final cardVisibility = await HomeCardPreferences.load();
    final needsSchedule =
        cardVisibility.showTodaySchedule ||
        cardVisibility.showExamCountdownCard;
    final needsRamadan =
        cardVisibility.showRamadanCard || cardVisibility.showTodaySchedule;
    final needsHoliday = cardVisibility.showTodaySchedule;

    final profileFuture = forceRefresh
        ? ProfileService().fetchProfile()
        : ProfileService().getProfile();
    final scheduleFuture = needsSchedule
        ? (forceRefresh
              ? ScheduleService().fetchStudentSchedule()
              : ScheduleService().getStudentSchedule())
        : Future<String?>.value(null);
    final ramadanFuture = needsRamadan
        ? RamadanTiming.getRamadanStatus(forceRefresh: forceRefresh)
        : Future<RamadanStatus>.value(const RamadanStatus(isRamadan: false));
    final holidayFuture = needsHoliday
        ? HolidayTiming.getTodayStatus(forceRefresh: forceRefresh)
        : Future<HolidayStatus>.value(HolidayStatus.empty);

    final results = await Future.wait<dynamic>([
      profileFuture,
      scheduleFuture,
      ramadanFuture,
      holidayFuture,
    ]);

    Map<String, String?>? profile = results[0] as Map<String, String?>?;
    String? scheduleJson = results[1] as String?;
    final ramadan = results[2] as RamadanStatus;
    final isRamadan = ramadan.isRamadan;
    final holidayStatus = results[3] as HolidayStatus;

    if (!forceRefresh &&
        (profile == null || (needsSchedule && scheduleJson == null))) {
      final fallbackResults = await Future.wait<dynamic>([
        profile == null
            ? ProfileService().fetchProfile()
            : Future.value(profile),
        scheduleJson == null && needsSchedule
            ? ScheduleService().fetchStudentSchedule()
            : Future.value(scheduleJson),
      ]);
      profile = fallbackResults[0] as Map<String, String?>?;
      scheduleJson = fallbackResults[1] as String?;
    }

    final photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
    final List<_ScheduleEntry> entries = [];
    final List<section.Section> sections = [];
    if (scheduleJson != null && scheduleJson.trim().isNotEmpty) {
      final decoded = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => section.Section.fromJson(e))
          .toList();
      sections.addAll(decoded);
      for (final section in decoded) {
        for (final s in section.sectionSchedule.classSchedules) {
          final adjusted = RamadanTiming.adjustRange(
            s.startTime,
            s.endTime,
            isRamadan: isRamadan,
          );
          entries.add(
            _ScheduleEntry(
              day: s.day,
              startTime: adjusted.startTime,
              endTime: adjusted.endTime,
              courseCode: section.courseCode,
              sectionName: section.sectionName,
              roomNumber: section.roomNumber,
              faculties: section.faculties,
            ),
          );
        }
      }
    }
    return _HomeData(
      profile: profile,
      entries: entries,
      photoUrl: photoUrl,
      sections: sections,
      isRamadan: isRamadan,
      ramadan: ramadan,
      holiday: holidayStatus,
      cardVisibility: cardVisibility,
    );
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (_isRefreshing) return;
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    _isRefreshing = true;
    try {
      final fresh = await _loadData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _latestData = fresh;
      });
      unawaited(_refreshCaptiveStatus());
      if (notify) {
        RefreshBus.instance.notify(reason: 'home_dashboard');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _refreshCaptiveStatus() async {
    if (_isCheckingCaptive) return;
    _isCheckingCaptive = true;
    try {
      if (AndroidNetworkAssist.isSupported) {
        await _consumePostConnectionEvent();
        final status = await AndroidNetworkAssist.getNetworkStatus();
        if (status != null) {
          _applyAndroidNetworkStatus(status);
          return;
        }
      }
      const next = CaptiveWifiStatus(
        state: CaptiveWifiState.unknown,
        httpStatusCode: null,
      );
      if (!mounted ||
          (_captiveStatus?.state == next.state &&
              _captiveStatus?.httpStatusCode == next.httpStatusCode)) {
        return;
      }
      setState(() {
        _captiveStatus = next;
      });
    } finally {
      _isCheckingCaptive = false;
    }
  }

  void _applyAndroidNetworkStatus(AndroidNetworkStatus status) {
    if (!mounted) return;
    final mapped = CaptiveWifiStatus(
      state: status.captive
          ? CaptiveWifiState.captive
          : status.validated
          ? CaptiveWifiState.validated
          : status.connected
          ? CaptiveWifiState.unknown
          : CaptiveWifiState.offline,
      httpStatusCode: null,
    );
    if (_captiveStatus?.state == mapped.state &&
        _captiveStatus?.httpStatusCode == mapped.httpStatusCode) {
      return;
    }
    setState(() {
      _captiveStatus = mapped;
    });
    if (status.captive) {
      unawaited(_maybeAutoOpenWifiAssistant(status));
    } else {
      _autoOpenedWifiAssistant = false;
    }
    unawaited(_maybeAutoExtendSession(status));
  }

  Future<void> _maybeAutoExtendSession(AndroidNetworkStatus status) async {
    if (!mounted || _isAutoExtendingSession) return;
    if (status.canExtendSession != true) return;
    final rawCaptiveWifiUrl = (status.captiveWifiUrl ?? '').trim();
    if (rawCaptiveWifiUrl.isEmpty) return;
    final captiveWifiUri = Uri.tryParse(rawCaptiveWifiUrl);
    if (captiveWifiUri == null ||
        !captiveWifiUri.hasAuthority ||
        (captiveWifiUri.scheme != 'http' && captiveWifiUri.scheme != 'https')) {
      return;
    }

    final expiryMillis = status.sessionExpiryTimeMillis;
    if (expiryMillis == null || expiryMillis <= 0) return;
    final remainingSeconds =
        ((expiryMillis - DateTime.now().millisecondsSinceEpoch) / 1000).floor();
    if (remainingSeconds > _autoSessionExtendThresholdSeconds) return;

    final now = DateTime.now();
    if (_lastAutoSessionExtendAt != null &&
        now.difference(_lastAutoSessionExtendAt!) <
            _autoSessionExtendCooldown) {
      return;
    }

    _isAutoExtendingSession = true;
    _lastAutoSessionExtendAt = now;
    try {
      await CaptiveWifiHttpService.instance.requestSessionExtension(
        captiveWifiUri,
      );
      if (!mounted) return;
      unawaited(_refreshCaptiveStatus());
    } catch (_) {
      // Best-effort background extension; ignore transient failures.
    } finally {
      _isAutoExtendingSession = false;
    }
  }

  Future<void> _maybeAutoOpenWifiAssistant(AndroidNetworkStatus status) async {
    if (_autoOpenedWifiAssistant || _isOpeningWifiAssistant || !mounted) return;
    if (status.transport != 'wifi') return;
    final creds = await CaptiveLoginStore.instance.read();
    if (!mounted || creds == null) return;
    final currentSsid = (status.ssid ?? '').trim();
    if (currentSsid.isEmpty) return;
    final now = DateTime.now();
    if (_lastAutoAssistantOpenAt != null &&
        now.difference(_lastAutoAssistantOpenAt!) < _autoAssistantCooldown) {
      return;
    }
    _autoOpenedWifiAssistant = true;
    _lastAutoAssistantOpenAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openWifiLoginAssistant();
    });
  }

  Future<void> _consumePostConnectionEvent() async {
    if (!AndroidNetworkAssist.isSupported || !mounted) return;
    final event = await AndroidNetworkAssist.getAndClearPostConnectionEvent();
    final pending = event['pending'] == true;
    if (!pending) return;
    final creds = await CaptiveLoginStore.instance.read();
    if (!mounted || creds == null) return;
    _autoOpenedWifiAssistant = true;
    _lastAutoAssistantOpenAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openWifiLoginAssistant();
    });
  }

  Future<void> _openWifiLoginAssistant() async {
    if (_isOpeningWifiAssistant || !mounted) return;
    _isOpeningWifiAssistant = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              const CaptiveWifiPage(autoOpenCaptiveWifiOnStart: true),
        ),
      );
    } finally {
      _isOpeningWifiAssistant = false;
    }
  }

  String _todayName() {
    switch (DateTime.now().weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

  _ExamCountdownData? _nextExamCountdown(List<section.Section> sections) {
    final now = DateTime.now();
    final exams = <_ExamCountdownData>[];
    for (final s in sections) {
      final schedule = s.sectionSchedule;
      final mid = BracuTime.parseDateTime(
        schedule.midExamDate,
        schedule.midExamStartTime,
      );
      if (mid != null) {
        exams.add(
          _ExamCountdownData(time: mid, courseCode: s.courseCode, type: 'Mid'),
        );
      }
      final fin = BracuTime.parseDateTime(
        schedule.finalExamDate,
        schedule.finalExamStartTime,
      );
      if (fin != null) {
        exams.add(
          _ExamCountdownData(
            time: fin,
            courseCode: s.courseCode,
            type: 'Final',
          ),
        );
      }
    }
    final upcoming = exams.where((e) => !e.time.isBefore(now)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (upcoming.isEmpty) return null;
    return upcoming.first;
  }

  int _timeToMinutes(String time) {
    return BracuTime.toMinutes(time) ?? 0;
  }

  _ScheduleEntry? _pickNextEntry(List<_ScheduleEntry> entries, int nowMinutes) {
    for (final entry in entries) {
      final start = _timeToMinutes(entry.startTime);
      final end = _timeToMinutes(entry.endTime);
      if (nowMinutes >= start && nowMinutes < end) {
        return entry;
      }
    }
    for (final entry in entries) {
      final start = _timeToMinutes(entry.startTime);
      if (start >= nowMinutes) {
        return entry;
      }
    }
    return null;
  }

  String? _nextRamadanTarget({String? sehri, String? iftar}) {
    DateTime? nextOccurrence(String? time) {
      final parsed = BracuTime.parseTime(time);
      if (parsed == null) return null;
      final now = DateTime.now();
      var target = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.hour,
        parsed.minute,
      );
      if (!target.isAfter(now)) {
        target = target.add(const Duration(days: 1));
      }
      return target;
    }

    final sehriAt = nextOccurrence(sehri);
    final iftarAt = nextOccurrence(iftar);
    if (sehriAt == null && iftarAt == null) return null;
    if (sehriAt == null) return 'Iftar';
    if (iftarAt == null) return 'Sehri';
    return sehriAt.isBefore(iftarAt) ? 'Sehri' : 'Iftar';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? Colors.black : _bgTop;
    final bgBottom = isDark ? Colors.black : _bgBottom;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: DecorBlob(
                color: _primary.withValues(alpha: 0.12),
                size: 200,
              ),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: DecorBlob(
                color: _accent.withValues(alpha: 0.10),
                size: 220,
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: FutureBuilder<_HomeData>(
                    future: _future,
                    builder: (context, snapshot) {
                      final data = _latestData ?? snapshot.data;
                      final profile = data?.profile ?? {};
                      final photoUrl = data?.photoUrl;
                      final ramadan =
                          data?.ramadan ??
                          const RamadanStatus(isRamadan: false);
                      final isRamadan = ramadan.isRamadan;
                      final nextCountdownTarget = _nextRamadanTarget(
                        sehri: ramadan.sehriEndsAt,
                        iftar: ramadan.iftarAt,
                      );
                      final holidayStatus =
                          data?.holiday ?? HolidayStatus.empty;
                      final cardVisibility =
                          data?.cardVisibility ?? HomeCardPreferences.defaults;
                      final isTodayHoliday = holidayStatus.isTodayHoliday;
                      final today = _todayName();
                      final todayDate = DateFormat(
                        'd MMMM, y',
                      ).format(DateTime.now());
                      final todayEntries =
                          (data?.entries ?? [])
                              .where(
                                (e) =>
                                    normalizeWeekday(e.day) ==
                                    normalizeWeekday(today),
                              )
                              .toList()
                            ..sort(
                              (a, b) =>
                                  _timeToMinutes(a.startTime) -
                                  _timeToMinutes(b.startTime),
                            );
                      final visibleEntries = isTodayHoliday
                          ? <_ScheduleEntry>[]
                          : todayEntries;
                      final nowMinutes = _timeToMinutes(
                        '${DateTime.now().hour}:${DateTime.now().minute}',
                      );
                      _ScheduleEntry? nextEntry;
                      if (visibleEntries.isNotEmpty) {
                        nextEntry = _pickNextEntry(visibleEntries, nowMinutes);
                      }
                      final nextExam = _nextExamCountdown(
                        data?.sections ?? const <section.Section>[],
                      );
                      return BracuRefreshScroll(
                        onRefresh: _handleRefresh,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TopBar(
                              name: profile['fullName'] ?? 'BRACU Student',
                              photoUrl: photoUrl,
                              onProfileTap: () =>
                                  widget.onNavigate(HomeTab.profile),
                            ),
                            if (_captiveStatus?.state ==
                                CaptiveWifiState.captive) ...[
                              const SizedBox(height: 12),
                              _CaptiveWifiBanner(
                                statusCode: _captiveStatus?.httpStatusCode,
                                onOpenLogin: _openWifiLoginAssistant,
                              ),
                            ],
                            const SizedBox(height: 18),
                            StudentOverviewCard(
                              studentId: profile['studentId'] ?? '',
                              shortCode: profile['shortCode'] ?? '',
                              department: profile['departmentName'] ?? '',
                              currentSemester: profile['currentSemester'] ?? '',
                              currentSessionSemesterId:
                                  profile['currentSessionSemesterId'] ?? '',
                              onOpenNotifications: () =>
                                  widget.onNavigate(HomeTab.notifications),
                              onOpenSettings: () =>
                                  widget.onNavigate(HomeTab.settings),
                              onLogout: widget.onLogout,
                              countdown:
                                  !cardVisibility.showExamCountdownCard ||
                                      nextExam == null
                                  ? null
                                  : InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => widget.onNavigate(
                                        HomeTab.examSchedule,
                                      ),
                                      child: ExamCountdownCard(
                                        title:
                                            nextExam.time
                                                    .difference(DateTime.now())
                                                    .inDays <=
                                                3
                                            ? '${nextExam.courseCode} ${nextExam.type} Exam'
                                            : '${nextExam.type} Exam',
                                        targetDateTime: nextExam.time,
                                      ),
                                    ),
                            ),
                            if (cardVisibility.showTodaySchedule) ...[
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () =>
                                    widget.onNavigate(HomeTab.studentSchedule),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Today is $today',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      todayDate,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (isTodayHoliday || visibleEntries.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: InkWell(
                                    onTap: () => widget.onNavigate(
                                      HomeTab.studentSchedule,
                                    ),
                                    child: _ScheduleTile(
                                      title: isTodayHoliday
                                          ? 'National Holiday'
                                          : 'No Class Today',
                                      subtitle: isTodayHoliday
                                          ? holidayStatus.displayNames
                                          : 'Enjoy your day off or check your schedule.',
                                      badge: isTodayHoliday ? 'OFF' : '--',
                                      color: _primary,
                                    ),
                                  ),
                                )
                              else
                                ...visibleEntries
                                    .take(3)
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: InkWell(
                                          onTap: () => widget.onNavigate(
                                            HomeTab.studentSchedule,
                                          ),
                                          child: _ScheduleTile(
                                            title: entry.courseCode,
                                            subtitle: formatTimeRange(
                                              entry.startTime,
                                              entry.endTime,
                                            ),
                                            trailing: entry.roomNumber,
                                            trailingSub: entry.faculties,
                                            badge: formatSectionBadge(
                                              entry.sectionName,
                                            ),
                                            color: _primary,
                                            isHighlighted: entry == nextEntry,
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                            if (cardVisibility.showRamadanCard && isRamadan)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: BracuCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (nextCountdownTarget != null) ...[
                                        _RamadanTopCountdown(
                                          ramadanDay: ramadan.ramadanDay,
                                          targetLabel: nextCountdownTarget,
                                          targetTime:
                                              nextCountdownTarget == 'Sehri'
                                              ? ramadan.sehriEndsAt
                                              : ramadan.iftarAt,
                                        ),
                                        Divider(
                                          height: 14,
                                          thickness: 1,
                                          color:
                                              BracuPalette.textSecondary(
                                                context,
                                              ).withValues(
                                                alpha:
                                                    Theme.of(
                                                          context,
                                                        ).brightness ==
                                                        Brightness.dark
                                                    ? 0.20
                                                    : 0.12,
                                              ),
                                        ),
                                      ],
                                      if (ramadan.sehriEndsAt != null ||
                                          ramadan.iftarAt != null) ...[
                                        Row(
                                          children: [
                                            if (ramadan.sehriEndsAt != null)
                                              Expanded(
                                                child: _RamadanHeroTime(
                                                  label: 'Sehri',
                                                  value: BracuTime.format(
                                                    ramadan.sehriEndsAt,
                                                  ),
                                                ),
                                              ),
                                            if (ramadan.sehriEndsAt != null &&
                                                ramadan.iftarAt != null)
                                              const SizedBox(width: 10),
                                            if (ramadan.iftarAt != null)
                                              Expanded(
                                                child: _RamadanHeroTime(
                                                  label: 'Iftar',
                                                  value: BracuTime.format(
                                                    ramadan.iftarAt,
                                                  ),
                                                  alignRight: true,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            if (cardVisibility.showQuickAccessSection) ...[
                              SizedBox(
                                height:
                                    cardVisibility.showRamadanCard && isRamadan
                                    ? 0
                                    : 10,
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(
                                    child: _SectionTitle(title: 'Quick Access'),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      await InAppReviewPrompt.openStoreListing();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            child: Icon(
                                              Icons.star_border_rounded,
                                              size: 17,
                                              color: BracuPalette.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Rate',
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: BracuPalette.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      await SharePlus.instance.share(
                                        ShareParams(
                                          text:
                                              'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect',
                                          subject:
                                              'PreConnect • Prepare. Connect. Succeed.',
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            child: Icon(
                                              Icons.share_outlined,
                                              size: 14,
                                              color: BracuPalette.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Share',
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: BracuPalette.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  const spacing = 12.0;
                                  final width =
                                      (constraints.maxWidth - spacing * 3) / 4;
                                  return Center(
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      runAlignment: WrapAlignment.center,
                                      spacing: spacing,
                                      runSpacing: spacing,
                                      children: [
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.person_outline,
                                          title: 'Profile',
                                          subtitle: 'Info & ID',
                                          color: _primary,
                                          onTap: () => widget.onNavigate(
                                            HomeTab.profile,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.schedule_outlined,
                                          title: 'Class',
                                          subtitle: 'Schedules',
                                          color: _accent,
                                          onTap: () => widget.onNavigate(
                                            HomeTab.studentSchedule,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.alarm_outlined,
                                          title: 'Alarm',
                                          subtitle: 'Reminders',
                                          color: const Color(0xFFFF8A34),
                                          onTap: () => widget.onNavigate(
                                            HomeTab.alarms,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.event_note_outlined,
                                          title: 'Exam',
                                          subtitle: 'Dates',
                                          color: const Color(0xFF7C56FF),
                                          onTap: () => widget.onNavigate(
                                            HomeTab.examSchedule,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.people_outline,
                                          title: 'Friends',
                                          subtitle: 'Schedules',
                                          color: const Color(0xFF5B8DEF),
                                          onTap: () => widget.onNavigate(
                                            HomeTab.friendSchedule,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.calendar_today_outlined,
                                          title: 'Events',
                                          subtitle: 'Calendar',
                                          color: const Color(0xFF00A86B),
                                          onTap: () => widget.onNavigate(
                                            HomeTab.calendar,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.school_outlined,
                                          title: 'Degree',
                                          subtitle: 'Progress',
                                          color: const Color(0xFF2C9DFF),
                                          onTap: () => widget.onNavigate(
                                            HomeTab.degreeProgress,
                                          ),
                                        ),
                                        QuickAccessCard(
                                          width: width,
                                          icon: Icons.more_horiz_rounded,
                                          title: 'More',
                                          subtitle: 'Options',
                                          color: const Color(0xFF00A8E8),
                                          onTap: () => widget.onNavigate(
                                            HomeTab.moreQuickAccess,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            BracuActionBannerCard(
                              icon: Icons.favorite_outline_rounded,
                              title: 'Support PreConnect',
                              subtitle: 'Open QR and funding instructions',
                              iconColor: const Color(0xFF00A8E8),
                              onTap: () => showBracuFundingSupportSheet(context),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptiveWifiBanner extends StatelessWidget {
  const _CaptiveWifiBanner({required this.onOpenLogin, this.statusCode});

  final VoidCallback onOpenLogin;
  final int? statusCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BracuPalette.primary.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_lock_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Captive Wi-Fi login required',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BracuPalette.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            statusCode == null
                ? 'Connected to Wi-Fi but internet is behind captive Wi-Fi.'
                : 'Connected to Wi-Fi but internet is behind captive Wi-Fi (probe: HTTP $statusCode).',
            style: TextStyle(
              fontSize: 12,
              color: BracuPalette.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: onOpenLogin,
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('One-Tap Captive Wi-Fi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.photoUrl,
    required this.onProfileTap,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.trim().characters.first : 'S';
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E6BE3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: photoUrl == null
                      ? Text(
                          initial.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedImage(
                            url: photoUrl!,
                            fit: BoxFit.cover,
                            width: 42,
                            height: 42,
                            filterQuality: FilterQuality.low,
                            placeholder: Center(
                              child: Text(
                                initial.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            error: Center(
                              child: Text(
                                initial.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome Back',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.of(context),
          builder: (context, mode, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return IconButton(
              tooltip: isDark ? 'Light mode' : 'Dark mode',
              onPressed: () => ThemeController.setTheme(
                context,
                isDark ? ThemeMode.light : ThemeMode.dark,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                color: BracuPalette.primary,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BracuPalette.textPrimary(context),
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    this.trailing,
    this.trailingSub,
    this.isHighlighted = false,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final String? trailing;
  final String? trailingSub;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuCard(
      isHighlighted: isHighlighted,
      highlightColor: BracuPalette.primary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rightColumnWidth =
              (constraints.maxWidth * 0.30).clamp(96.0, 128.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionBadge(label: badge, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: rightColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        trailing!,
                        textAlign: TextAlign.right,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      if (trailingSub != null &&
                          trailingSub!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          trailingSub!,
                          textAlign: TextAlign.right,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RamadanHeroTime extends StatelessWidget {
  const _RamadanHeroTime({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  final String label;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final icon = label.toLowerCase() == 'sehri'
        ? Icons.nightlight_round
        : Icons.wb_sunny_outlined;
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: BracuPalette.textSecondary(context)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: BracuPalette.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: BracuPalette.textPrimary(context),
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _RamadanTopCountdown extends StatelessWidget {
  const _RamadanTopCountdown({
    required this.ramadanDay,
    required this.targetLabel,
    required this.targetTime,
  });

  final int? ramadanDay;
  final String targetLabel;
  final String? targetTime;

  @override
  Widget build(BuildContext context) {
    if (targetTime == null || targetTime!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: StreamBuilder<int>(
        stream: Stream<int>.periodic(
          const Duration(seconds: 1),
          (tick) => tick,
        ),
        builder: (context, snapshot) {
          final now = DateTime.now();
          final remaining = _durationTo(targetTime!, now);
          if (remaining == null) return const SizedBox.shrink();
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$targetLabel • ${BracuTime.format(targetTime)}',
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ramadanDay == null
                          ? 'Ramadan'
                          : 'Ramadan Day $ramadanDay',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RamadanCountdownDigital(remaining: remaining),
            ],
          );
        },
      ),
    );
  }

  Duration? _durationTo(String targetTime, DateTime now) {
    final parsed = BracuTime.parseTime(targetTime);
    if (parsed == null) return null;
    var target = DateTime(
      now.year,
      now.month,
      now.day,
      parsed.hour,
      parsed.minute,
    );
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }
}

class _RamadanCountdownDigital extends StatelessWidget {
  const _RamadanCountdownDigital({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = remaining.inSeconds;
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds ~/ 60) % 60;
    final seconds = safeSeconds % 60;

    Widget cell(String value, String label) {
      return SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    final units = <({String value, String label})>[
      (value: hours.toString().padLeft(2, '0'), label: 'Hours'),
      (value: minutes.toString().padLeft(2, '0'), label: 'Minutes'),
      (value: seconds.toString().padLeft(2, '0'), label: 'Seconds'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          cell(units[i].value, units[i].label),
          if (i != units.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _HomeData {
  _HomeData({
    required this.profile,
    required this.entries,
    required this.photoUrl,
    required this.sections,
    required this.isRamadan,
    required this.ramadan,
    required this.holiday,
    required this.cardVisibility,
  });

  final Map<String, String?>? profile;
  final List<_ScheduleEntry> entries;
  final String? photoUrl;
  final List<section.Section> sections;
  final bool isRamadan;
  final RamadanStatus ramadan;
  final HolidayStatus holiday;
  final HomeCardVisibility cardVisibility;

  _HomeData copyWith({HomeCardVisibility? cardVisibility}) {
    return _HomeData(
      profile: profile,
      entries: entries,
      photoUrl: photoUrl,
      sections: sections,
      isRamadan: isRamadan,
      ramadan: ramadan,
      holiday: holiday,
      cardVisibility: cardVisibility ?? this.cardVisibility,
    );
  }
}

class _ScheduleEntry {
  _ScheduleEntry({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
  });

  final String day;
  final String startTime;
  final String endTime;
  final String courseCode;
  final String sectionName;
  final String roomNumber;
  final String faculties;
}

class _ExamCountdownData {
  _ExamCountdownData({
    required this.time,
    required this.courseCode,
    required this.type,
  });

  final DateTime time;
  final String courseCode;
  final String type;
}

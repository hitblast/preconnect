part of 'package:preconnect/pages/home.dart';

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({required this.onNavigate, required this.onLogout});

  final void Function(HomeTab tab) onNavigate;
  final Future<void> Function() onLogout;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> with RefreshBusState {
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
  Future<_CampusMapData?>? _campusMapFuture;

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
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    _networkStatusSubscription?.cancel();
    _captiveAutoTimer?.cancel();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('home_dashboard')) {
      return;
    }
    if (isRefreshingFrom('home_card_settings_changed')) {
      unawaited(_reloadCardVisibilityOnly());
      unawaited(_refreshCaptiveStatus());
      return;
    }
    if (isRefreshingFrom('auth')) {
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
    Map<String, ExamScheduleOverride> examOverrides =
        const <String, ExamScheduleOverride>{};
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

      if (cardVisibility.showExamCountdownCard && sections.isNotEmpty) {
        examOverrides = await ExamScheduleService().getOverridesForSections(
          sections,
          forceRefresh: forceRefresh,
        );
      }
    }
    return _HomeData(
      profile: profile,
      entries: entries,
      photoUrl: photoUrl,
      sections: sections,
      examOverrides: examOverrides,
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

  _ExamCountdownData? _nextExamCountdown(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final examService = ExamScheduleService();
    final now = DateTime.now();
    final exams = <_ExamCountdownData>[];
    for (final s in sections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final mid = BracuTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (mid != null) {
        exams.add(
          _ExamCountdownData(time: mid, courseCode: s.courseCode, type: 'Mid'),
        );
      }
      final fin = BracuTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
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

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<_TodayExamEntry> _todayExamEntries(
    List<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final examService = ExamScheduleService();
    final today = DateTime.now();
    final exams = <_TodayExamEntry>[];
    for (final s in sections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final mid = BracuTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (mid != null && _isSameDate(mid, today)) {
        exams.add(
          _TodayExamEntry(
            dateTime: mid,
            courseCode: s.courseCode,
            type: 'Mid',
            sectionName: s.sectionName,
            faculties: s.faculties,
            startTime: resolved.midStartTime,
            endTime: resolved.midEndTime,
            room: resolved.midRoomNumber,
          ),
        );
      }
      final fin = BracuTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (fin != null && _isSameDate(fin, today)) {
        exams.add(
          _TodayExamEntry(
            dateTime: fin,
            courseCode: s.courseCode,
            type: 'Final',
            sectionName: s.sectionName,
            faculties: s.faculties,
            startTime: resolved.finalStartTime,
            endTime: resolved.finalEndTime,
            room: resolved.finalRoomNumber,
          ),
        );
      }
    }
    exams.sort((a, b) {
      return ExamSorting.compareExamEntries(
        typeA: a.type,
        typeB: b.type,
        dateTimeA: a.dateTime,
        dateTimeB: b.dateTime,
        courseCodeA: a.courseCode,
        courseCodeB: b.courseCode,
        sectionNameA: a.sectionName,
        sectionNameB: b.sectionName,
      );
    });
    return exams;
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

  Future<_CampusMapData?> _fetchCampusMap({bool forceRefresh = false}) async {
    final payload = await ScraperDataService().fetchMap(
      path: '/data/map',
      cacheKey: 'scraper_campus_map_v1',
      ttl: const Duration(hours: 12),
      forceRefresh: forceRefresh,
    );
    if (payload == null) return null;
    return _CampusMapData.fromJson(payload);
  }

  Future<void> _openCampusMapSheet() async {
    _campusMapFuture ??= _fetchCampusMap();
    if (!mounted) return;
    await showBracuBottomSheet<void>(
      context,
      title: 'Campus Map',
      subtitle: 'Directions, highlights and key contacts',
      builder: (sheetContext, textPrimary, textSecondary) {
        return FutureBuilder<_CampusMapData?>(
          future: _campusMapFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: BracuLoading());
            }
            final mapData = snapshot.data;
            if (mapData == null) {
              final sheetScroll = bracuBottomSheetScrollController(context);
              return ListView(
                controller: sheetScroll,
                children: [
                  Text(
                    'Campus map data is unavailable right now.',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }
            final sheetScroll = bracuBottomSheetScrollController(context);

            Widget sectionTitle(String value) => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                value,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            );

            Widget minimalBlock({required Widget child}) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BracuPalette.card(sheetContext).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: textSecondary.withValues(alpha: 0.16),
                  ),
                ),
                child: child,
              );
            }

            Widget actionButton({
              required IconData icon,
              required String label,
              required VoidCallback? onPressed,
            }) {
              return OutlinedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BracuPalette.primary,
                  side: BorderSide(
                    color: BracuPalette.primary.withValues(alpha: 0.52),
                    width: 1.1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            return ListView(
              controller: sheetScroll,
              children: [
                minimalBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mapData.campusName.isEmpty
                            ? 'BRAC University Campus'
                            : mapData.campusName,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (mapData.address.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          mapData.address,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final buttonWidth = (constraints.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.directions_rounded,
                            label: 'Open Map',
                            onPressed: mapData.googleMapsUrl.isEmpty
                                ? null
                                : () => openExternalUrl(
                                    sheetContext,
                                    mapData.googleMapsUrl,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.open_in_new_rounded,
                            label: 'Campus Life',
                            onPressed: mapData.sourceUrl.isEmpty
                                ? null
                                : () => openExternalUrl(
                                    sheetContext,
                                    mapData.sourceUrl,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.alternate_email_rounded,
                            label: 'Email',
                            onPressed: mapData.primaryEmail.isEmpty
                                ? null
                                : () => openMailComposer(
                                    sheetContext,
                                    mapData.primaryEmail,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.content_copy_rounded,
                            label: 'Copy Phone',
                            onPressed: mapData.primaryPhone.isEmpty
                                ? null
                                : () => copyToClipboard(
                                    sheetContext,
                                    mapData.primaryPhone,
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (mapData.highlights.isNotEmpty) ...[
                  sectionTitle('Highlights'),
                  ...mapData.highlights.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: BracuPalette.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (mapData.offices.isNotEmpty) ...[
                  sectionTitle('General Contacts'),
                  ...mapData.offices.map((office) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: minimalBlock(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              office.office,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (office.emails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...office.emails.map(
                                (email) => Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        email,
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          openMailComposer(sheetContext, email),
                                      icon: const Icon(
                                        Icons.email_outlined,
                                        size: 18,
                                      ),
                                      tooltip: 'Email',
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 4),
                              Text(
                                'No email listed',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
                if (mapData.emergencyContacts.isNotEmpty) ...[
                  sectionTitle('Emergency Contacts'),
                  ...mapData.emergencyContacts.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: minimalBlock(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (item.services.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.services,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            if (item.phones.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...item.phones.map(
                                (phone) => Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        phone,
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          copyToClipboard(sheetContext, phone),
                                      icon: const Icon(
                                        Icons.content_copy_rounded,
                                        size: 18,
                                      ),
                                      tooltip: 'Copy phone',
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 4),
                              Text(
                                'No phone listed',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        );
      },
    );
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
                        data?.examOverrides ??
                            const <String, ExamScheduleOverride>{},
                      );
                      final todayExams = _todayExamEntries(
                        data?.sections ?? const <section.Section>[],
                        data?.examOverrides ??
                            const <String, ExamScheduleOverride>{},
                      );
                      final now = DateTime.now();
                      _TodayExamEntry? nextTodayExam;
                      for (final exam in todayExams) {
                        if (!exam.dateTime.isBefore(now)) {
                          nextTodayExam = exam;
                          break;
                        }
                      }
                      nextTodayExam ??= todayExams.isNotEmpty
                          ? todayExams.first
                          : null;
                      return BracuRefreshScroll(
                        onRefresh: _handleRefresh,
                        showScrollTopButton: false,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TopBar(
                              name: profile['fullName'] ?? 'BRACU Student',
                              photoUrl: photoUrl,
                              onOpenNotifications: () =>
                                  widget.onNavigate(HomeTab.notifications),
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
                                onTap: () => widget.onNavigate(
                                  todayExams.isNotEmpty
                                      ? HomeTab.examSchedule
                                      : HomeTab.studentSchedule,
                                ),
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
                              if (todayExams.isNotEmpty)
                                ...todayExams
                                    .take(3)
                                    .map(
                                      (exam) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: InkWell(
                                          onTap: () => widget.onNavigate(
                                            HomeTab.examSchedule,
                                          ),
                                          child: _ScheduleTile(
                                            title:
                                                '${exam.courseCode} ${exam.type} Exam',
                                            subtitle: formatTimeRange(
                                              exam.startTime,
                                              exam.endTime,
                                            ),
                                            trailing: exam.room,
                                            trailingSub: exam.faculties,
                                            badge: formatSectionBadge(
                                              exam.sectionName,
                                            ),
                                            color: _accent,
                                            isHighlighted:
                                                exam == nextTodayExam,
                                          ),
                                        ),
                                      ),
                                    )
                              else if (isTodayHoliday || visibleEntries.isEmpty)
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
                                          onTap: () =>
                                              widget.onNavigate(HomeTab.alarms),
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
                                          icon: Icons.developer_mode_outlined,
                                          title: 'Dev',
                                          subtitle: 'About Us',
                                          color: const Color(0xFF2C9DFF),
                                          onTap: () =>
                                              widget.onNavigate(HomeTab.devs),
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
                              icon: Icons.map_outlined,
                              title: 'Campus Map & Contacts',
                              subtitle:
                                  'Locations and emergency details',
                              iconColor: const Color(0xFF22B573),
                              onTap: _openCampusMapSheet,
                            ),
                            const SizedBox(height: 12),
                            BracuActionBannerCard(
                              icon: Icons.favorite_outline_rounded,
                              title: 'Support PreConnect',
                              subtitle: 'Open QR and funding instructions',
                              iconColor: const Color(0xFF00A8E8),
                              onTap: () =>
                                  showBracuFundingSupportSheet(context),
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

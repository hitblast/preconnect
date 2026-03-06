import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';
import 'package:preconnect/tools/time_utils.dart';

class SeatStatusPage extends StatefulWidget {
  const SeatStatusPage({super.key});

  @override
  State<SeatStatusPage> createState() => _SeatStatusPageState();
}

class _SeatStatusPageState extends State<SeatStatusPage>
    with WidgetsBindingObserver {
  static const List<String> _weekdayOrder = <String>[
    'SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
  ];

  final SeatStatusService _service = SeatStatusService();
  final List<_SeatStatusCardData> _cards = <_SeatStatusCardData>[];
  final List<_SeatStatusCardData> _visibleCards = <_SeatStatusCardData>[];
  final Map<int, SeatStatusDetailsResponse> _detailsCache =
      <int, SeatStatusDetailsResponse>{};
  final Map<String, SeatStatusStaffInfo> _staffInfoByInitial =
      <String, SeatStatusStaffInfo>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isInitialLoading = true;
  String _searchQuery = '';
  bool _cacheLoaded = false;
  bool _isAppForeground = true;
  bool _isDetailsRefreshing = false;
  bool _isResolvingStaffInfo = false;
  bool _isStreamConnecting = false;
  bool _isSavingCache = false;
  bool _availableOnly = false;
  String _selectedDayFilter = '';
  final Set<String> _pendingInitials = <String>{};
  http.Client? _streamClient;
  StreamSubscription<String>? _streamSubscription;
  Timer? _streamReconnectTimer;
  Timer? _streamRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final next = _searchController.text.trim().toLowerCase();
        _updateSearchQuery(next);
      });
    });
    unawaited(_reloadAll());
    _isSavingCache = _service.isSavingDetailsCache.value;
    _service.isSavingDetailsCache.addListener(_onCacheSaveStateChanged);
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    _updatePollingStrategy();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    _stopSeatStatusStream();
    _service.isSavingDetailsCache.removeListener(_onCacheSaveStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      _updatePollingStrategy();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isAppForeground = false;
      _updatePollingStrategy();
    }
  }

  void _onActiveTabChanged() {
    if (!mounted) return;
    _updatePollingStrategy();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'seat_status') {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  void _onCacheSaveStateChanged() {
    if (!mounted) return;
    final next = _service.isSavingDetailsCache.value;
    if (next == _isSavingCache) return;
    setState(() {
      _isSavingCache = next;
    });
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    await _refreshDetailsFromApi();
    if (notify) {
      RefreshBus.instance.notify(reason: 'seat_status');
    }
  }

  Future<void> _reloadAll() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }
    if (!_cacheLoaded) {
      final cached = await _service.loadCachedDetails(
        maxAge: const Duration(hours: 1),
      );
      if (cached.isNotEmpty) {
        _detailsCache
          ..clear()
          ..addAll(cached);
        await _loadCachedStaffInfoForDetails(cached.values);
        _queueStaffInfoResolve(cached.values);
        final cachedCards = _buildCardsFromDetailsMap(cached);
        _sortCardsByCourseAndSection(cachedCards);
        _applyCardsSnapshot(cachedCards, isInitialLoading: false);
      }
      _cacheLoaded = true;
    }

    await _refreshDetailsFromApi();
    if (!mounted) return;
    if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  List<_SeatStatusCardData> _buildCardsFromDetailsMap(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) {
    final sectionIds = _visibleSectionIdsFromDetails(detailsMap).toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));
    return sectionIds.map((sectionId) {
      final cached = detailsMap[sectionId];
      if (cached == null) {
        return _buildFallbackCard(sectionId: sectionId, remaining: 0);
      }
      return _buildCardFromDetails(sectionId: sectionId, details: cached);
    }).toList();
  }

  Future<void> _applyDetailsUpdate(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) async {
    if (!mounted || detailsMap.isEmpty) return;
    _detailsCache
      ..clear()
      ..addAll(detailsMap);
    await _loadCachedStaffInfoForDetails(detailsMap.values);
    _queueStaffInfoResolve(detailsMap.values);
    final updated = _buildCardsFromDetailsMap(detailsMap);
    _sortCardsByCourseAndSection(updated);
    if (_areCardListsDifferent(_cards, updated)) {
      _applyCardsSnapshot(updated, isInitialLoading: false);
    } else if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  _SeatStatusCardData _buildFallbackCard({
    required int sectionId,
    required int remaining,
  }) {
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: 'SEC$sectionId',
      sectionName: '--',
      courseName: 'Loading section details...',
      facultyInitial: 'TBA',
      facultyName: '',
      facultyEmail: '',
      facultyMeta: '',
      credits: 0,
      room: '',
      classSchedule: const <SeatStatusClassSchedule>[],
      labSchedule: const <SeatStatusClassSchedule>[],
      labRoom: '',
      midExamDate: null,
      midExamStartTime: null,
      midExamEndTime: null,
      finalExamDate: null,
      finalExamStartTime: null,
      finalExamEndTime: null,
      remaining: remaining,
      consumed: 0,
      total: 0,
      searchToken: 'sec$sectionId loading tba $remaining',
    );
  }

  Set<int> _visibleSectionIdsFromDetails(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) {
    final childIds = <int>{};
    for (final details in detailsMap.values) {
      final childId = details.childSection?.sectionId ?? 0;
      if (childId > 0) childIds.add(childId);
    }
    return detailsMap.keys.where((id) => !childIds.contains(id)).toSet();
  }

  _SeatStatusCardData _buildCardFromDetails({
    required int sectionId,
    required SeatStatusDetailsResponse details,
  }) {
    final main = details.section;
    final lab = details.childSection;
    final total = main.capacity;
    final resolvedRemaining = (total - main.consumedSeat).clamp(0, total);
    final resolvedConsumed = (total - resolvedRemaining).clamp(0, total);
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: _pickNonEmpty(main.courseCode, 'SEC$sectionId'),
      sectionName: _pickNonEmpty(main.sectionName, '--'),
      courseName: _pickNonEmpty(main.name, 'Section $sectionId'),
      facultyInitial: _pickNonEmpty(main.faculties, 'TBA'),
      facultyName: _facultyNameForInitial(main.faculties),
      facultyEmail: _facultyEmailForInitial(main.faculties),
      facultyMeta: _facultyMetaForInitial(main.faculties),
      credits: main.courseCredit,
      room: _pickNonEmpty(main.roomNumber, ''),
      classSchedule: main.sectionSchedule.classSchedules,
      labSchedule:
          lab?.sectionSchedule.classSchedules ??
          const <SeatStatusClassSchedule>[],
      labRoom: _pickNonEmpty(lab?.roomNumber, ''),
      midExamDate: main.sectionSchedule.midExamDate,
      midExamStartTime: main.sectionSchedule.midExamStartTime,
      midExamEndTime: main.sectionSchedule.midExamEndTime,
      finalExamDate: main.sectionSchedule.finalExamDate,
      finalExamStartTime: main.sectionSchedule.finalExamStartTime,
      finalExamEndTime: main.sectionSchedule.finalExamEndTime,
      remaining: resolvedRemaining,
      consumed: resolvedConsumed,
      total: total,
      searchToken: _buildSearchToken(
        sectionId: sectionId,
        courseCode: _pickNonEmpty(main.courseCode, 'SEC$sectionId'),
        sectionName: _pickNonEmpty(main.sectionName, '--'),
        courseName: _pickNonEmpty(main.name, 'Section $sectionId'),
        facultyInitial: _pickNonEmpty(main.faculties, 'TBA'),
        facultyName: _facultyNameForInitial(main.faculties),
        facultyEmail: _facultyEmailForInitial(main.faculties),
        facultyMeta: _facultyMetaForInitial(main.faculties),
        room: _pickNonEmpty(main.roomNumber, ''),
        labRoom: _pickNonEmpty(lab?.roomNumber, ''),
        classSchedule: main.sectionSchedule.classSchedules,
        labSchedule:
            lab?.sectionSchedule.classSchedules ??
            const <SeatStatusClassSchedule>[],
        midExamDate: main.sectionSchedule.midExamDate,
        midExamStartTime: main.sectionSchedule.midExamStartTime,
        midExamEndTime: main.sectionSchedule.midExamEndTime,
        finalExamDate: main.sectionSchedule.finalExamDate,
        finalExamStartTime: main.sectionSchedule.finalExamStartTime,
        finalExamEndTime: main.sectionSchedule.finalExamEndTime,
        total: total,
        consumed: resolvedConsumed,
        remaining: resolvedRemaining,
      ),
    );
  }

  String _buildSearchToken({
    required int sectionId,
    required String courseCode,
    required String sectionName,
    required String courseName,
    required String facultyInitial,
    required String facultyName,
    required String facultyEmail,
    required String facultyMeta,
    required String room,
    required String labRoom,
    required List<SeatStatusClassSchedule> classSchedule,
    required List<SeatStatusClassSchedule> labSchedule,
    required String? midExamDate,
    required String? midExamStartTime,
    required String? midExamEndTime,
    required String? finalExamDate,
    required String? finalExamStartTime,
    required String? finalExamEndTime,
    required int total,
    required int consumed,
    required int remaining,
  }) {
    final scheduleToken = _buildScheduleSearchToken(classSchedule, labSchedule);
    final examToken =
        '${midExamDate ?? ''} ${midExamStartTime ?? ''} ${midExamEndTime ?? ''} '
        '${finalExamDate ?? ''} ${finalExamStartTime ?? ''} ${finalExamEndTime ?? ''}';
    return '$courseCode $sectionName $courseName '
            '$facultyInitial $facultyName $facultyEmail $facultyMeta '
            '$room $labRoom $sectionId $total $consumed $remaining '
            '$scheduleToken $examToken'
        .toLowerCase();
  }

  String _buildScheduleSearchToken(
    List<SeatStatusClassSchedule> classSchedule,
    List<SeatStatusClassSchedule> labSchedule,
  ) {
    final chunks = <String>[];
    for (final item in <SeatStatusClassSchedule>[
      ...classSchedule,
      ...labSchedule,
    ]) {
      final dayRaw = item.day.trim();
      final dayPretty = formatWeekdayTitle(item.day);
      final startRaw = item.startTime.trim();
      final endRaw = item.endTime.trim();
      chunks.add('$dayRaw $dayPretty $startRaw $endRaw');
    }
    return chunks.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final showLoadingState =
        _isInitialLoading || (_cards.isEmpty && _isDetailsRefreshing);
    final hasCards = _cards.isNotEmpty;
    final hasVisibleCards = _visibleCards.isNotEmpty;
    final itemCount = hasVisibleCards ? _visibleCards.length + 1 : 2;

    return BracuPageScaffold(
      title: 'Seat Status',
      subtitle: 'Live Sections',
      icon: Icons.insights_outlined,
      body: Stack(
        children: [
          BracuRefreshListBuilder(
            onRefresh: _handleRefresh,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildFilterHeader(context);
              }
              if (showLoadingState) {
                return const Padding(
                  padding: EdgeInsets.only(top: 28),
                  child: Center(
                    child: BracuLoading(label: 'Loading seats...'),
                  ),
                );
              }
              if (!hasCards) {
                return const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: BracuEmptyState(message: 'No section data available'),
                );
              }
              if (!hasVisibleCards) {
                return const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: BracuEmptyState(message: 'No matching section found'),
                );
              }
              final item = _visibleCards[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SeatStatusCard(item: item),
              );
            },
          ),
          if (_isSavingCache)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.14),
                child: const Center(
                  child: BracuLoading(label: 'Saving seat cache...'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(context),
          const SizedBox(height: 10),
          _buildFilterActions(context),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hintColor = scheme.onSurface.withValues(alpha: 0.64);
    final textColor = scheme.onSurface;
    final borderColor = scheme.onSurface.withValues(alpha: 0.24);
    return TextField(
      key: ValueKey<String>('seat-search-${Theme.of(context).brightness.name}'),
      controller: _searchController,
      style: TextStyle(color: textColor),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by anything...',
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(Icons.search, color: hintColor),
        suffixIcon: _searchQuery.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () => _searchController.clear(),
                icon: Icon(Icons.close, color: hintColor),
              ),
        filled: true,
        fillColor: BracuPalette.card(context).withValues(alpha: 0.92),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
    );
  }

  Widget _buildFilterActions(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildAvailabilityFilterAction(),
          _buildDayFilterAction(context),
        ],
      ),
    );
  }

  Widget _buildAvailabilityFilterAction() {
    return _FilterChip(
      icon: Icons.event_available_outlined,
      label: 'Available',
      selected: _availableOnly,
      onTap: () => _setAvailableFilter(!_availableOnly),
      showArrow: false,
    );
  }

  Widget _buildDayFilterAction(BuildContext context) {
    final label = _selectedDayFilter.isEmpty
        ? 'Any Day'
        : formatWeekdayTitle(_selectedDayFilter);
    final labels = <String>[
      'Any Day',
      ..._weekdayOrder.map(formatWeekdayTitle),
    ];
    final menuWidth = compactPopupMenuWidth(context, labels, maxWidth: 320);
    return PopupMenuButton<String>(
      tooltip: 'Filter by day',
      constraints: BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
      onSelected: _setDayFilter,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        compactPopupMenuItem<String>(value: '', label: 'Any Day'),
        ..._weekdayOrder.map(
          (day) => compactPopupMenuItem<String>(
            value: day,
            label: formatWeekdayTitle(day),
          ),
        ),
      ],
      child: _FilterChip(
        icon: Icons.calendar_today_outlined,
        label: label,
        selected: _selectedDayFilter.isNotEmpty,
      ),
    );
  }

  void _setAvailableFilter(bool next) {
    if (next == _availableOnly) return;
    _refreshVisibleCards(availableOnly: next);
  }

  void _setDayFilter(String next) {
    if (next == _selectedDayFilter) return;
    _refreshVisibleCards(dayFilter: next);
  }

  void _refreshVisibleCards({
    bool? availableOnly,
    String? dayFilter,
    String? query,
  }) {
    final resolvedAvailableOnly = availableOnly ?? _availableOnly;
    final resolvedDayFilter = dayFilter ?? _selectedDayFilter;
    final resolvedQuery = query ?? _searchQuery;
    final nextVisible = _filterCards(
      _cards,
      resolvedQuery,
      availableOnly: resolvedAvailableOnly,
      dayFilter: resolvedDayFilter,
    );
    final filtersChanged =
        resolvedAvailableOnly != _availableOnly ||
        resolvedDayFilter != _selectedDayFilter ||
        resolvedQuery != _searchQuery;
    if (!filtersChanged && !_areCardListsDifferent(_visibleCards, nextVisible)) {
      return;
    }
    setState(() {
      _availableOnly = resolvedAvailableOnly;
      _selectedDayFilter = resolvedDayFilter;
      _searchQuery = resolvedQuery;
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
    });
  }

  List<_SeatStatusCardData> _filterCards(
    List<_SeatStatusCardData> source,
    String query, {
    required bool availableOnly,
    required String dayFilter,
  }) {
    final q = query.trim().toLowerCase();
    return source.where((card) {
      if (q.isNotEmpty && !card.searchToken.contains(q)) return false;
      if (availableOnly && card.remaining <= 0) return false;

      if (dayFilter.isNotEmpty) {
        final schedules = <SeatStatusClassSchedule>[
          ...card.classSchedule,
          ...card.labSchedule,
        ];
        final hasDay = schedules.any(
          (entry) => normalizeWeekday(entry.day) == dayFilter,
        );
        if (!hasDay) return false;
      }
      return true;
    }).toList();
  }

  void _updateSearchQuery(String nextQuery) {
    if (nextQuery == _searchQuery) return;
    _refreshVisibleCards(query: nextQuery);
  }

  void _applyCardsSnapshot(
    List<_SeatStatusCardData> nextCards, {
    bool? isInitialLoading,
  }) {
    final nextVisible = _filterCards(
      nextCards,
      _searchQuery,
      availableOnly: _availableOnly,
      dayFilter: _selectedDayFilter,
    );
    if (!mounted) return;
    final cardsChanged = _areCardListsDifferent(_cards, nextCards);
    final visibleChanged = _areCardListsDifferent(_visibleCards, nextVisible);
    final loadingChanged =
        isInitialLoading != null && _isInitialLoading != isInitialLoading;
    if (!cardsChanged && !visibleChanged && !loadingChanged) {
      return;
    }
    setState(() {
      _cards
        ..clear()
        ..addAll(nextCards);
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
      if (isInitialLoading != null) {
        _isInitialLoading = isInitialLoading;
      }
    });
  }

  void _sortCardsByCourseAndSection(List<_SeatStatusCardData> cards) {
    cards.sort((a, b) {
      final codeCmp = a.courseCode.compareTo(b.courseCode);
      if (codeCmp != 0) return codeCmp;
      final sectionCmp = _sectionOrder(
        a.sectionName,
      ).compareTo(_sectionOrder(b.sectionName));
      if (sectionCmp != 0) return sectionCmp;
      return a.sectionName.compareTo(b.sectionName);
    });
  }

  int _compareSectionIdsByNaming(int a, int b) {
    final aDetails = _detailsCache[a]?.section;
    final bDetails = _detailsCache[b]?.section;
    final aCode = _pickNonEmpty(aDetails?.courseCode, 'SEC$a');
    final bCode = _pickNonEmpty(bDetails?.courseCode, 'SEC$b');
    final codeCmp = aCode.compareTo(bCode);
    if (codeCmp != 0) return codeCmp;
    final aSection = _pickNonEmpty(aDetails?.sectionName, '$a');
    final bSection = _pickNonEmpty(bDetails?.sectionName, '$b');
    final sectionCmp = _sectionOrder(
      aSection,
    ).compareTo(_sectionOrder(bSection));
    if (sectionCmp != 0) return sectionCmp;
    return aSection.compareTo(bSection);
  }

  bool _areCardListsDifferent(
    List<_SeatStatusCardData> a,
    List<_SeatStatusCardData> b,
  ) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (!_isSameCard(a[i], b[i])) return true;
    }
    return false;
  }

  bool _isSameCard(_SeatStatusCardData x, _SeatStatusCardData y) {
    if (x.sectionId != y.sectionId) return false;
    if (x.courseCode != y.courseCode) return false;
    if (x.sectionName != y.sectionName) return false;
    if (x.courseName != y.courseName) return false;
    if (x.facultyInitial != y.facultyInitial) return false;
    if (x.facultyName != y.facultyName) return false;
    if (x.facultyEmail != y.facultyEmail) return false;
    if (x.facultyMeta != y.facultyMeta) return false;
    if (x.credits != y.credits) return false;
    if (x.room != y.room) return false;
    if (x.labRoom != y.labRoom) return false;
    if (x.midExamDate != y.midExamDate) return false;
    if (x.midExamStartTime != y.midExamStartTime) return false;
    if (x.midExamEndTime != y.midExamEndTime) return false;
    if (x.finalExamDate != y.finalExamDate) return false;
    if (x.finalExamStartTime != y.finalExamStartTime) return false;
    if (x.finalExamEndTime != y.finalExamEndTime) return false;
    if (x.remaining != y.remaining) return false;
    if (x.consumed != y.consumed) return false;
    if (x.total != y.total) return false;
    if (x.searchToken != y.searchToken) return false;
    if (!_sameSchedules(x.classSchedule, y.classSchedule)) return false;
    if (!_sameSchedules(x.labSchedule, y.labSchedule)) return false;
    return true;
  }

  bool _sameSchedules(
    List<SeatStatusClassSchedule> a,
    List<SeatStatusClassSchedule> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].day != b[i].day) return false;
      if (a[i].startTime != b[i].startTime) return false;
      if (a[i].endTime != b[i].endTime) return false;
    }
    return true;
  }

  void _updatePollingStrategy() {
    final shouldRun =
        _isAppForeground &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus;
    if (!shouldRun) {
      _stopSeatStatusStream();
      return;
    }
    _startSeatStatusStream();
    if (_cards.isEmpty) {
      unawaited(_refreshDetailsFromApi());
    }
  }

  Future<void> _refreshDetailsFromApi() async {
    if (_isDetailsRefreshing) return;
    if (mounted && _cards.isEmpty) {
      setState(() {
        _isDetailsRefreshing = true;
      });
    } else {
      _isDetailsRefreshing = true;
    }
    try {
      final details = await _service.fetchAllSectionsDetailsFromApi();
      if (details.isNotEmpty) {
        await _applyDetailsUpdate(details);
      }
    } catch (_) {
      if (_isInitialLoading && mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    } finally {
      if (mounted && _cards.isEmpty) {
        setState(() {
          _isDetailsRefreshing = false;
        });
      } else {
        _isDetailsRefreshing = false;
      }
    }
  }

  void _startSeatStatusStream() {
    if (_streamSubscription != null || _isStreamConnecting) return;
    unawaited(_connectSeatStatusStream());
  }

  void _stopSeatStatusStream() {
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _streamRefreshDebounce?.cancel();
    _streamRefreshDebounce = null;
    unawaited(_streamSubscription?.cancel());
    _streamSubscription = null;
    _streamClient?.close();
    _streamClient = null;
    _isStreamConnecting = false;
  }

  Future<void> _connectSeatStatusStream() async {
    if (!_isAppForeground ||
        HomeTabRegistry.activeTab.value != HomeTab.seatStatus) {
      return;
    }
    if (_streamSubscription != null || _isStreamConnecting) return;
    _isStreamConnecting = true;
    _streamClient?.close();
    _streamClient = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse(_service.seatStatusStreamUrl),
      )..headers['Accept'] = 'text/event-stream';
      final response = await _streamClient!
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('SSE returned ${response.statusCode}');
      }
      _streamSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onStreamLine,
            onError: (_) => _scheduleStreamReconnect(),
            onDone: _scheduleStreamReconnect,
            cancelOnError: true,
          );
    } catch (_) {
      _scheduleStreamReconnect();
    } finally {
      _isStreamConnecting = false;
    }
  }

  void _onStreamLine(String line) {
    if (!line.startsWith('data:')) return;
    if (!_isAppForeground ||
        HomeTabRegistry.activeTab.value != HomeTab.seatStatus) {
      return;
    }
    _streamRefreshDebounce?.cancel();
    _streamRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_refreshDetailsFromApi());
    });
  }

  void _scheduleStreamReconnect() {
    unawaited(_streamSubscription?.cancel());
    _streamSubscription = null;
    _streamClient?.close();
    _streamClient = null;
    _streamReconnectTimer?.cancel();
    final shouldRun =
        _isAppForeground &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus;
    if (!shouldRun) return;
    _streamReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _startSeatStatusStream();
    });
  }

  void _queueStaffInfoResolve(
    Iterable<SeatStatusDetailsResponse> detailsValues,
  ) {
    for (final details in detailsValues) {
      final main = details.section.faculties.trim().toUpperCase();
      if (main.isNotEmpty) _pendingInitials.add(main);
      final child = (details.childSection?.faculties ?? '')
          .trim()
          .toUpperCase();
      if (child.isNotEmpty) _pendingInitials.add(child);
    }
    if (_pendingInitials.isEmpty) return;
    if (_isResolvingStaffInfo) return;
    unawaited(_resolvePendingStaffInfo());
  }

  Future<void> _loadCachedStaffInfoForDetails(
    Iterable<SeatStatusDetailsResponse> detailsValues,
  ) async {
    final initials = <String>{};
    for (final details in detailsValues) {
      final main = details.section.faculties.trim().toUpperCase();
      if (main.isNotEmpty) initials.add(main);
      final child = (details.childSection?.faculties ?? '')
          .trim()
          .toUpperCase();
      if (child.isNotEmpty) initials.add(child);
    }
    if (initials.isEmpty) return;
    final cached = await _service.loadCachedStaffInfoByInitials(initials);
    if (cached.isEmpty) return;
    _staffInfoByInitial.addAll(cached);
  }

  Future<void> _resolvePendingStaffInfo() async {
    if (_isResolvingStaffInfo) return;
    if (_pendingInitials.isEmpty) return;
    _isResolvingStaffInfo = true;
    try {
      while (_pendingInitials.isNotEmpty) {
        final batch = _pendingInitials.take(20).toList();
        _pendingInitials.removeAll(batch);
        final changed = await _resolveStaffInfoForInitials(batch.toSet());
        if (changed && mounted && _detailsCache.isNotEmpty) {
          final refreshed = _buildCardsFromDetailsMap(_detailsCache);
          _sortCardsByCourseAndSection(refreshed);
          _applyCardsSnapshot(refreshed, isInitialLoading: false);
        }
      }
    } finally {
      _isResolvingStaffInfo = false;
    }
  }

  Future<bool> _resolveStaffInfoForInitials(Set<String> initials) async {
    if (initials.isEmpty) return false;
    final missing = initials
        .where((key) => !_staffInfoByInitial.containsKey(key))
        .toSet();
    if (missing.isEmpty) return false;
    final resolved = await _service.resolveStaffInfoByInitials(missing);
    if (resolved.isEmpty) return false;
    var changed = false;
    for (final entry in resolved.entries) {
      if (_staffInfoByInitial.containsKey(entry.key)) continue;
      _staffInfoByInitial[entry.key] = entry.value;
      changed = true;
    }
    return changed;
  }

  String _facultyNameForInitial(String facultyInitial) {
    final key = facultyInitial.trim().toUpperCase();
    return (_staffInfoByInitial[key]?.staffName ?? '').trim();
  }

  String _facultyEmailForInitial(String facultyInitial) {
    final key = facultyInitial.trim().toUpperCase();
    return (_staffInfoByInitial[key]?.email ?? '').trim();
  }

  String _facultyMetaForInitial(String facultyInitial) {
    final key = facultyInitial.trim().toUpperCase();
    final info = _staffInfoByInitial[key];
    if (info == null) return '';
    final chunks = <String>[];
    if (info.departmentId != null) chunks.add('Dept #${info.departmentId}');
    if (info.designationId != null) {
      chunks.add('Designation #${info.designationId}');
    }
    return chunks.join(' • ');
  }
}

class _SeatStatusCard extends StatelessWidget {
  const _SeatStatusCard({required this.item});

  final _SeatStatusCardData item;

  Widget _facultyAvatar(BuildContext context) {
    final label = item.facultyInitial.trim().isEmpty
        ? '?'
        : item.facultyInitial.trim().toUpperCase();
    return _FacultyAvatar(initial: item.facultyInitial, fallbackLabel: label);
  }

  Future<void> _openFacultyEmail(BuildContext context) async {
    await openMailComposer(context, item.facultyEmail);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.courseCode} - ${item.sectionName}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.courseName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                        children: [
                          TextSpan(text: item.facultyInitial),
                          const TextSpan(text: '  •  '),
                          TextSpan(text: '${item.credits} credits'),
                        ],
                      ),
                    ),
                    if (item.facultyName.isNotEmpty ||
                        item.facultyEmail.isNotEmpty ||
                        item.facultyMeta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _facultyAvatar(context),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.facultyName.isNotEmpty)
                                    Text(
                                      item.facultyName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: textSecondary,
                                      ),
                                    ),
                                  if (item.facultyEmail.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: GestureDetector(
                                        onTap: () => _openFacultyEmail(context),
                                        child: Text(
                                          item.facultyEmail,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (item.facultyMeta.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        item.facultyMeta,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        showAppSnackBar(context, 'Seat alerts coming soon.');
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.notifications_outlined,
                          color: BracuPalette.textPrimary(context),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SeatScheduleBlock(
            title: 'Class',
            lines: _scheduleLines(item.classSchedule),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(color: textSecondary, fontSize: 11),
              children: [
                const TextSpan(text: 'Room: '),
                TextSpan(
                  text: item.room.isEmpty ? '--' : item.room,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SeatScheduleBlock(
            title: 'Lab',
            lines: _scheduleLines(
              item.labSchedule,
              fallback: const <String>['-'],
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(color: textSecondary, fontSize: 11),
              children: [
                const TextSpan(text: 'Room: '),
                TextSpan(
                  text: item.labRoom.isEmpty ? '--' : item.labRoom,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ExamInfo(
                  label: 'Mid',
                  date: item.midExamDate,
                  start: item.midExamStartTime,
                  end: item.midExamEndTime,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ExamInfo(
                  label: 'Final',
                  date: item.finalExamDate,
                  start: item.finalExamStartTime,
                  end: item.finalExamEndTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SeatMetric(
                  value: item.remaining,
                  label: 'Remaining',
                  color: item.remaining <= 0
                      ? BracuPalette.danger
                      : textPrimary,
                ),
              ),
              Expanded(
                child: _SeatMetric(
                  value: item.consumed,
                  label: 'Consumed',
                  color: textPrimary,
                ),
              ),
              Expanded(
                child: _SeatMetric(
                  value: item.total,
                  label: 'Total Seats',
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _scheduleLines(
    List<SeatStatusClassSchedule> schedules, {
    List<String> fallback = const <String>['-'],
  }) {
    if (schedules.isEmpty) return fallback;
    final lines = schedules.map((entry) {
      final day = formatWeekdayTitle(entry.day);
      final time = formatTimeRange(entry.startTime, entry.endTime);
      return '$day $time';
    }).toList();
    return lines;
  }
}

class _FacultyAvatar extends StatefulWidget {
  const _FacultyAvatar({
    required this.initial,
    required this.fallbackLabel,
  });

  final String initial;
  final String fallbackLabel;

  @override
  State<_FacultyAvatar> createState() => _FacultyAvatarState();
}

class _FacultyAvatarState extends State<_FacultyAvatar> {
  static const String _facultyImageApiBase =
      'https://preconnect.app/api/faculty';
  static const double _avatarSize = 52;
  static final Map<String, String?> _resolvedImageUrls = <String, String?>{};
  static final Map<String, Future<String?>> _inFlight =
      <String, Future<String?>>{};

  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolvedUrl = _resolvedImageUrls[_normalizedInitial];
    if (_resolvedUrl == null && _normalizedInitial != null) {
      unawaited(_resolveImageUrl());
    }
  }

  @override
  void didUpdateWidget(covariant _FacultyAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial == widget.initial) return;
    _resolvedUrl = _resolvedImageUrls[_normalizedInitial];
    if (_resolvedUrl == null && _normalizedInitial != null) {
      unawaited(_resolveImageUrl());
    }
  }

  String? get _normalizedInitial {
    final normalized = widget.initial.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalized.isEmpty || normalized == 'tba') {
      return null;
    }
    return normalized;
  }

  Future<void> _resolveImageUrl() async {
    final initial = _normalizedInitial;
    if (initial == null) return;
    final existing = _inFlight[initial];
    final future = existing ?? _fetchImageUrl(initial);
    if (existing == null) {
      _inFlight[initial] = future;
    }
    try {
      final resolved = await future;
      _resolvedImageUrls[initial] = resolved;
      if (!mounted || _normalizedInitial != initial) return;
      setState(() {
        _resolvedUrl = resolved;
      });
    } finally {
      if (identical(_inFlight[initial], future)) {
        _inFlight.remove(initial);
      }
    }
  }

  Future<String?> _fetchImageUrl(String initial) async {
    try {
      final response = await http.get(
        Uri.parse('$_facultyImageApiBase/$initial'),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = response.body.trim();
      if (body.isEmpty) return null;
      if (body.startsWith('http://') || body.startsWith('https://')) {
        return body;
      }
      final decoded = jsonDecode(body);
      if (decoded is String) return decoded.trim().isEmpty ? null : decoded;
      if (decoded is Map) {
        for (final key in <String>['url', 'image', 'imageUrl', 'photoUrl']) {
          final value = '${decoded[key] ?? ''}'.trim();
          if (value.startsWith('http://') || value.startsWith('https://')) {
            return value;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Widget _fallbackAvatar() {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.fallbackLabel,
        style: const TextStyle(
          color: BracuPalette.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _fallbackAvatar();
    final resolvedUrl = _resolvedUrl;
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: _avatarSize,
        height: _avatarSize,
        child: CachedImage(
          url: resolvedUrl,
          fit: BoxFit.cover,
          width: _avatarSize,
          height: _avatarSize,
          placeholder: fallback,
          error: fallback,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
    this.showArrow = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? BracuPalette.primary.withValues(alpha: 0.14)
              : BracuPalette.card(context).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? BracuPalette.primary.withValues(alpha: 0.45)
                : BracuPalette.textSecondary(context).withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? BracuPalette.primary
                  : BracuPalette.textSecondary(context),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: BracuPalette.textSecondary(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeatScheduleBlock extends StatelessWidget {
  const _SeatScheduleBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        for (final line in lines)
          Text(
            line,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ExamInfo extends StatelessWidget {
  const _ExamInfo({
    required this.label,
    required this.date,
    required this.start,
    required this.end,
  });

  final String label;
  final String? date;
  final String? start;
  final String? end;

  @override
  Widget build(BuildContext context) {
    final dateValue = _formatExamDate(date);
    final timeValue = _formatExamTime(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          dateValue,
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          timeValue,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  String _formatExamDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '--';
    final parsed = BracuTime.parseDate(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y').format(parsed);
  }

  String _formatExamTime(String? start, String? end) {
    final range = formatTimeRange(start, end);
    if (range.isEmpty) return '--';
    return range;
  }
}

class _SeatMetric extends StatelessWidget {
  const _SeatMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SeatStatusCardData {
  const _SeatStatusCardData({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.courseName,
    required this.facultyInitial,
    required this.facultyName,
    required this.facultyEmail,
    required this.facultyMeta,
    required this.credits,
    required this.room,
    required this.classSchedule,
    required this.labSchedule,
    required this.labRoom,
    required this.midExamDate,
    required this.midExamStartTime,
    required this.midExamEndTime,
    required this.finalExamDate,
    required this.finalExamStartTime,
    required this.finalExamEndTime,
    required this.remaining,
    required this.consumed,
    required this.total,
    required this.searchToken,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String courseName;
  final String facultyInitial;
  final String facultyName;
  final String facultyEmail;
  final String facultyMeta;
  final int credits;
  final String room;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
  final String labRoom;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;
  final int remaining;
  final int consumed;
  final int total;
  final String searchToken;

  _SeatStatusCardData copyWith({int? remaining, int? consumed, int? total}) {
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: courseCode,
      sectionName: sectionName,
      courseName: courseName,
      facultyInitial: facultyInitial,
      facultyName: facultyName,
      facultyEmail: facultyEmail,
      facultyMeta: facultyMeta,
      credits: credits,
      room: room,
      classSchedule: classSchedule,
      labSchedule: labSchedule,
      labRoom: labRoom,
      midExamDate: midExamDate,
      midExamStartTime: midExamStartTime,
      midExamEndTime: midExamEndTime,
      finalExamDate: finalExamDate,
      finalExamStartTime: finalExamStartTime,
      finalExamEndTime: finalExamEndTime,
      remaining: remaining ?? this.remaining,
      consumed: consumed ?? this.consumed,
      total: total ?? this.total,
      searchToken: searchToken,
    );
  }
}

int _sectionOrder(String sectionName) {
  final number = RegExp(r'\d+').firstMatch(sectionName)?.group(0);
  if (number == null) return 9999;
  return int.tryParse(number) ?? 9999;
}

String _pickNonEmpty(String? primary, String fallback) {
  final value = (primary ?? '').trim();
  if (value.isNotEmpty) return value;
  return fallback.trim();
}

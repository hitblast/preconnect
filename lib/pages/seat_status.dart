import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
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
  bool _isSeatMapRefreshing = false;
  bool _isDetailsSyncing = false;
  bool _isResolvingStaffInfo = false;
  bool _availableOnly = false;
  String _selectedDayFilter = '';
  final Set<String> _pendingInitials = <String>{};
  Map<int, int> _latestSeatMap = <int, int>{};

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
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    _updatePollingStrategy();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
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

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    await _refreshSeatMapFromApi();
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
    final cachedSeatMapFuture = _service.loadCachedSeatMap(
      maxAge: const Duration(hours: 1),
    );
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
      }
      _cacheLoaded = true;
    }
    final cachedSeatMap = await cachedSeatMapFuture;

    if (cachedSeatMap.isNotEmpty && mounted) {
      _latestSeatMap = Map<int, int>.from(cachedSeatMap);
      final cachedCards = _buildCardsFromSeatMap(cachedSeatMap);
      _applyCardsSnapshot(cachedCards, isInitialLoading: false);
    }

    await _refreshSeatMapFromApi();
    unawaited(_syncMissingDetails(chunkSize: 36, concurrency: 8));
    if (!mounted) return;
    if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  List<_SeatStatusCardData> _buildCardsFromSeatMap(Map<int, int> seatMap) {
    final sectionIds = _visibleSectionIds(seatMap).toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));
    return sectionIds
        .where((sectionId) => _detailsCache.containsKey(sectionId))
        .map((sectionId) {
          final cached = _detailsCache[sectionId];
          return _buildCardFromDetails(
            sectionId: sectionId,
            details: cached!,
            remaining: seatMap[sectionId],
          );
        })
        .toList();
  }

  Future<void> _applySeatMapUpdate(Map<int, int> seatMap) async {
    if (!mounted || seatMap.isEmpty) return;
    _latestSeatMap = Map<int, int>.from(seatMap);

    final nextIds = _visibleSectionIds(seatMap);
    final detailsForVisible = nextIds
        .map((id) => _detailsCache[id])
        .whereType<SeatStatusDetailsResponse>()
        .toList();
    _queueStaffInfoResolve(detailsForVisible);
    final existingIds = _cards.map((c) => c.sectionId).toSet();

    final updated = _cards.where((c) => nextIds.contains(c.sectionId)).map((c) {
      final seatMapValue = seatMap[c.sectionId];
      final detailsConsumed =
          _detailsCache[c.sectionId]?.section.consumedSeat ?? c.consumed;
      final remaining = seatMapValue == null
          ? c.remaining
          : _resolveRemainingFromSeatMap(
              total: c.total,
              seatMapValue: seatMapValue,
              detailsConsumed: detailsConsumed,
            );
      final consumed = c.total > 0
          ? (c.total - remaining).clamp(0, c.total)
          : c.consumed;
      return c.copyWith(remaining: remaining, consumed: consumed);
    }).toList();

    final addedIds = nextIds.difference(existingIds).toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));
    for (final sectionId in addedIds) {
      final cached = _detailsCache[sectionId];
      if (cached == null) continue;
      updated.add(
        _buildCardFromDetails(
          sectionId: sectionId,
          details: cached,
          remaining: seatMap[sectionId],
        ),
      );
    }

    _sortCardsByCourseAndSection(updated);
    if (_areCardListsDifferent(_cards, updated)) {
      _applyCardsSnapshot(updated, isInitialLoading: false);
    } else if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  Set<int> _visibleSectionIds(Map<int, int> seatMap) {
    final childIds = <int>{};
    for (final details in _detailsCache.values) {
      final childId = details.childSection?.sectionId ?? 0;
      if (childId > 0) childIds.add(childId);
    }
    return seatMap.keys.where((id) => !childIds.contains(id)).toSet();
  }

  _SeatStatusCardData _buildCardFromDetails({
    required int sectionId,
    required SeatStatusDetailsResponse details,
    required int? remaining,
  }) {
    final main = details.section;
    final lab = details.childSection;
    final total = main.capacity;
    final fallbackRemaining = (total - main.consumedSeat).clamp(0, total);
    final resolvedRemaining = remaining == null
        ? fallbackRemaining
        : _resolveRemainingFromSeatMap(
            total: total,
            seatMapValue: remaining,
            detailsConsumed: main.consumedSeat,
          );
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

  int _resolveRemainingFromSeatMap({
    required int total,
    required int seatMapValue,
    required int detailsConsumed,
  }) {
    if (total <= 0) return 0;
    final normalized = seatMapValue.clamp(0, total);
    final asRemaining = normalized;
    final asConsumed = (total - normalized).clamp(0, total);
    final fallbackRemaining = (total - detailsConsumed).clamp(0, total);
    final remainingDiff = (asRemaining - fallbackRemaining).abs();
    final consumedDiff = (asConsumed - fallbackRemaining).abs();
    if (consumedDiff < remainingDiff) return asConsumed;
    return asRemaining;
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
        '${formatDate(midExamDate)} ${formatTimeRange(midExamStartTime, midExamEndTime)} '
        '${formatDate(finalExamDate)} ${formatTimeRange(finalExamStartTime, finalExamEndTime)}';
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
      final start = formatTime(item.startTime);
      final end = formatTime(item.endTime);
      final range = formatTimeRange(item.startTime, item.endTime);
      chunks.add('$dayRaw $dayPretty $start $end $range');
    }
    return chunks.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Seat Status',
      subtitle: 'Live Sections',
      icon: Icons.insights_outlined,
      body: _isInitialLoading
          ? BracuRefreshPlaceholder(
              onRefresh: _handleRefresh,
              child: const BracuLoading(label: 'Loading seats...'),
            )
          : _cards.isEmpty
          ? BracuRefreshListBuilder(
              onRefresh: _handleRefresh,
              itemCount: 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildFilterHeader(context);
                }
                return const BracuCard(
                  child: BracuEmptyState(message: 'No section data available'),
                );
              },
            )
          : BracuRefreshListBuilder(
              onRefresh: _handleRefresh,
              itemCount: _visibleCards.isEmpty ? 2 : _visibleCards.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildFilterHeader(context);
                }
                if (_visibleCards.isEmpty) {
                  return const BracuCard(
                    child: BracuEmptyState(
                      message: 'No matching section found',
                    ),
                  );
                }
                final item = _visibleCards[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SeatStatusCard(item: item),
                );
              },
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
    return TextField(
      controller: _searchController,
      style: TextStyle(color: BracuPalette.textPrimary(context)),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by anything...',
        hintStyle: TextStyle(color: BracuPalette.textSecondary(context)),
        prefixIcon: Icon(
          Icons.search,
          color: BracuPalette.textSecondary(context),
        ),
        suffixIcon: _searchQuery.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () => _searchController.clear(),
                icon: Icon(
                  Icons.close,
                  color: BracuPalette.textSecondary(context),
                ),
              ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: BracuPalette.textSecondary(context).withValues(alpha: 0.24),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BracuPalette.primary),
        ),
      ),
    );
  }

  Widget _buildFilterActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildAvailabilityFilterAction(),
        _buildDayFilterAction(context),
      ],
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
    final menuWidth = _popupMenuWidth(
      context,
      labels,
      minWidth: 170,
      maxWidth: 320,
    );
    return PopupMenuButton<String>(
      tooltip: 'Filter by day',
      initialValue: _selectedDayFilter,
      constraints: BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
      onSelected: _setDayFilter,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: '',
          checked: _selectedDayFilter.isEmpty,
          child: _menuItemLabel('Any Day'),
        ),
        ..._weekdayOrder.map(
          (day) => CheckedPopupMenuItem<String>(
            value: day,
            checked: day == _selectedDayFilter,
            child: _menuItemLabel(formatWeekdayTitle(day)),
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

  double _popupMenuWidth(
    BuildContext context,
    List<String> labels, {
    required double minWidth,
    required double maxWidth,
  }) {
    const style = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
    var maxTextWidth = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.width > maxTextWidth) {
        maxTextWidth = painter.width;
      }
    }
    final screenMax = MediaQuery.sizeOf(context).width - 20;
    final effectiveMax = math.min(maxWidth, screenMax);
    return (maxTextWidth + 110).clamp(minWidth, effectiveMax);
  }

  Widget _menuItemLabel(String label) {
    return Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    );
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
    if (!_isAppForeground) return;
    if (HomeTabRegistry.activeTab.value != HomeTab.seatStatus) return;
    unawaited(_refreshSeatMapFromApi());
    unawaited(_syncMissingDetails(chunkSize: 24, concurrency: 6));
  }

  Future<void> _refreshSeatMapFromApi() async {
    if (_isSeatMapRefreshing) return;
    _isSeatMapRefreshing = true;
    try {
      final previousMap = Map<int, int>.from(_latestSeatMap);
      final seatMap = await _service.fetchSeatMapFromApi();
      if (seatMap.isNotEmpty) {
        final changedIds = _changedSectionIds(previousMap, seatMap);
        await _applySeatMapUpdate(seatMap);
        if (previousMap.isNotEmpty && changedIds.isNotEmpty) {
          await _refreshChangedDetails(changedIds, concurrency: 8);
        }
        unawaited(_syncMissingDetails(chunkSize: 24, concurrency: 6));
      }
    } catch (_) {
      if (_isInitialLoading && mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    } finally {
      _isSeatMapRefreshing = false;
    }
  }

  Future<void> _syncMissingDetails({
    int chunkSize = 10,
    int concurrency = 4,
  }) async {
    if (_isDetailsSyncing) return;
    if (_latestSeatMap.isEmpty) return;
    _isDetailsSyncing = true;
    try {
      final takeCount = math.max(1, chunkSize);
      while (true) {
        final missing =
            _latestSeatMap.keys
                .where((id) => !_detailsCache.containsKey(id))
                .toList()
              ..sort((a, b) => a.compareTo(b));
        if (missing.isEmpty) return;

        final picked = missing.take(takeCount).toList();
        final fetched = await _service.fetchDetailsForSectionIdsFromApi(
          picked,
          concurrency: concurrency,
        );
        if (fetched.isEmpty) return;
        _detailsCache.addAll(fetched);
        await _loadCachedStaffInfoForDetails(fetched.values);
        _queueStaffInfoResolve(fetched.values);
        await _applySeatMapUpdate(_latestSeatMap);
      }
    } catch (_) {
    } finally {
      _isDetailsSyncing = false;
    }
  }

  Set<int> _changedSectionIds(Map<int, int> before, Map<int, int> after) {
    final changed = <int>{};
    for (final id in after.keys) {
      final prev = before[id];
      final next = after[id];
      if (prev == null || prev != next) {
        changed.add(id);
      }
    }
    return changed;
  }

  Future<void> _refreshChangedDetails(
    Set<int> sectionIds, {
    int concurrency = 8,
  }) async {
    if (sectionIds.isEmpty) return;
    try {
      final refreshed = await _service.fetchDetailsForSectionIdsFromApi(
        sectionIds.toList(),
        concurrency: concurrency,
      );
      if (refreshed.isEmpty) return;
      _detailsCache.addAll(refreshed);
      await _loadCachedStaffInfoForDetails(refreshed.values);
      _queueStaffInfoResolve(refreshed.values);
      await _applySeatMapUpdate(_latestSeatMap);
    } catch (_) {}
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
        if (changed && mounted && _latestSeatMap.isNotEmpty) {
          final refreshed = _buildCardsFromSeatMap(_latestSeatMap);
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
                    if (item.facultyName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.facultyName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
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

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
  final SeatStatusService _service = SeatStatusService();
  final List<_SeatStatusCardData> _cards = <_SeatStatusCardData>[];
  final List<_SeatStatusCardData> _visibleCards = <_SeatStatusCardData>[];
  final Map<int, SeatStatusDetailsResponse> _detailsCache =
      <int, SeatStatusDetailsResponse>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _apiRefreshTimer;
  Timer? _detailsSyncTimer;
  bool _isInitialLoading = true;
  String _searchQuery = '';
  bool _cacheLoaded = false;
  bool _isAppForeground = true;
  int _detailsSyncCursor = 0;
  bool _isSeatMapRefreshing = false;
  bool _isDetailsSyncing = false;
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
    _stopLocalPolling();
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
    await _syncMissingDetailsChunk(chunkSize: 36, concurrency: 8);
    if (!mounted) return;
    if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  List<_SeatStatusCardData> _buildCardsFromSeatMap(Map<int, int> seatMap) {
    final sectionIds = seatMap.keys.toList()
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

    final nextIds = seatMap.keys.toSet();
    final existingIds = _cards.map((c) => c.sectionId).toSet();

    final updated = _cards.where((c) => nextIds.contains(c.sectionId)).map((c) {
      final remaining = seatMap[c.sectionId] ?? c.remaining;
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

  _SeatStatusCardData _buildCardFromDetails({
    required int sectionId,
    required SeatStatusDetailsResponse details,
    required int? remaining,
  }) {
    final main = details.section;
    final lab = details.childSection;
    final total = main.capacity;
    final resolvedRemaining = remaining ?? (total - main.consumedSeat);
    final resolvedConsumed = (total - resolvedRemaining).clamp(0, total);
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: _pickNonEmpty(main.courseCode, 'SEC$sectionId'),
      sectionName: _pickNonEmpty(main.sectionName, '--'),
      courseName: _pickNonEmpty(main.name, 'Section $sectionId'),
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
        facultyInitial: _pickNonEmpty(main.faculties, ''),
        room: _pickNonEmpty(main.roomNumber, ''),
        labRoom: _pickNonEmpty(lab?.roomNumber, ''),
      ),
    );
  }

  String _buildSearchToken({
    required int sectionId,
    required String courseCode,
    required String sectionName,
    required String courseName,
    required String facultyInitial,
    required String room,
    required String labRoom,
  }) {
    return '$courseCode $sectionName $courseName $facultyInitial $room $labRoom $sectionId'
        .toLowerCase();
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
              itemCount: 3,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildSearchField(context);
                }
                if (index == 1) {
                  return const SizedBox(height: 12);
                }
                return const BracuCard(
                  child: BracuEmptyState(message: 'No section data available'),
                );
              },
            )
          : BracuRefreshListBuilder(
              onRefresh: _handleRefresh,
              itemCount: _visibleCards.isEmpty ? 3 : _visibleCards.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildSearchField(context);
                }
                if (index == 1) {
                  return const SizedBox(height: 12);
                }
                if (_visibleCards.isEmpty) {
                  return const BracuCard(
                    child: BracuEmptyState(
                      message: 'No matching section found',
                    ),
                  );
                }
                final item = _visibleCards[index - 2];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SeatStatusCard(item: item),
                );
              },
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

  List<_SeatStatusCardData> _filterCards(
    List<_SeatStatusCardData> source,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source.where((card) => card.searchToken.contains(q)).toList();
  }

  void _updateSearchQuery(String nextQuery) {
    if (nextQuery == _searchQuery) return;
    final nextVisible = _filterCards(_cards, nextQuery);
    setState(() {
      _searchQuery = nextQuery;
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
    });
  }

  void _applyCardsSnapshot(
    List<_SeatStatusCardData> nextCards, {
    bool? isInitialLoading,
  }) {
    final nextVisible = _filterCards(nextCards, _searchQuery);
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
    if (_isAppForeground) {
      _startLocalPolling();
      return;
    }
    _stopLocalPolling();
  }

  void _startLocalPolling() {
    _apiRefreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshSeatMapFromApi());
    });
    _detailsSyncTimer ??= Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_syncMissingDetailsChunk(chunkSize: 10));
    });
    unawaited(_refreshSeatMapFromApi());
  }

  void _stopLocalPolling() {
    _apiRefreshTimer?.cancel();
    _apiRefreshTimer = null;
    _detailsSyncTimer?.cancel();
    _detailsSyncTimer = null;
  }

  Future<void> _refreshSeatMapFromApi() async {
    if (_isSeatMapRefreshing) return;
    _isSeatMapRefreshing = true;
    try {
      final seatMap = await _service.fetchSeatMapFromApi();
      if (seatMap.isNotEmpty) {
        await _applySeatMapUpdate(seatMap);
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

  Future<void> _syncMissingDetailsChunk({
    int chunkSize = 10,
    int concurrency = 4,
  }) async {
    if (_isDetailsSyncing) return;
    if (_latestSeatMap.isEmpty) return;
    final missing =
        _latestSeatMap.keys
            .where((id) => !_detailsCache.containsKey(id))
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (missing.isEmpty) return;

    _isDetailsSyncing = true;
    try {
      final take = math.min(chunkSize, missing.length);
      if (_detailsSyncCursor >= missing.length) {
        _detailsSyncCursor = 0;
      }
      final picked = <int>[];
      var idx = _detailsSyncCursor;
      for (var i = 0; i < take; i++) {
        picked.add(missing[idx]);
        idx = (idx + 1) % missing.length;
      }
      _detailsSyncCursor = idx;

      final fetched = await _service.fetchDetailsForSectionIdsFromApi(
        picked,
        concurrency: concurrency,
      );
      if (fetched.isEmpty) return;
      _detailsCache.addAll(fetched);
      await _applySeatMapUpdate(_latestSeatMap);
    } catch (_) {
    } finally {
      _isDetailsSyncing = false;
    }
  }
}

class _SeatStatusCard extends StatelessWidget {
  const _SeatStatusCard({required this.item});

  final _SeatStatusCardData item;

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
                        children: [TextSpan(text: '${item.credits} credits')],
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
                        decoration: const BoxDecoration(
                          color: BracuPalette.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
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

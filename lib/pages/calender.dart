import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/calendar_service.dart';
import 'package:preconnect/model/calendar_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class CalenderPage extends StatefulWidget {
  const CalenderPage({super.key});

  @override
  State<CalenderPage> createState() => _CalenderPageState();
}

class _CalenderPageState extends State<CalenderPage> {
  late Future<CalendarFeed?> _future;
  CalendarFeed? _lastFeed;
  GlobalKey? _highlightKey;
  String? _lastHighlightToken;
  bool _didScroll = false;
  bool _scrollRetry = false;

  @override
  void initState() {
    super.initState();
    _future = CalendarService().getCalendar();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'calender') return;
    _refresh(notify: false);
  }

  Future<void> _refresh({bool notify = true}) async {
    final next = CalendarService().fetchCalendar(fallback: _lastFeed);
    setState(() {
      _didScroll = false;
      _scrollRetry = false;
      _future = next;
    });
    final refreshed = await next;
    if (!mounted) return;
    setState(() {
      _lastFeed = refreshed;
    });
    if (notify) {
      RefreshBus.instance.notify(reason: 'calender');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Calender',
      subtitle: 'Semester Events',
      icon: Icons.calendar_today_outlined,
      body: FutureBuilder<CalendarFeed?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _lastFeed == null) {
            return buildRefreshLoadingState(
              onRefresh: _refresh,
              topSpacing: 180,
            );
          }

          final feed = _lastFeed ?? snapshot.data;
          final items = feed?.items ?? const <CalendarEntry>[];
          if (items.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              topSpacing: 180,
              message: 'No calender data available.',
            );
          }

          final grouped = _groupByDate(items);
          final today = DateTime.now();
          final todayKey = DateTime(today.year, today.month, today.day);
          final sortedDates = grouped.keys.toList()..sort();
          DateTime? targetDate;
          if (grouped.containsKey(todayKey)) {
            targetDate = todayKey;
          } else {
            for (final date in sortedDates) {
              if (!date.isBefore(todayKey)) {
                targetDate = date;
                break;
              }
            }
            targetDate ??= sortedDates.isNotEmpty ? sortedDates.last : null;
          }
          final highlightToken = targetDate == null
              ? null
              : 'focus_${targetDate.year}_${targetDate.month}_${targetDate.day}';
          _highlightKey = null;
          if (highlightToken != null && highlightToken != _lastHighlightToken) {
            _lastHighlightToken = highlightToken;
            _didScroll = false;
            _scrollRetry = false;
          }
          final children = <Widget>[];
          for (final entry in grouped.entries) {
            final isTargetSection =
                targetDate != null && entry.key == targetDate;
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: BracuSectionTitle(
                                title: _dayLabel(entry.key),
                              ),
                            ),
                            Text(
                              formatLongDate(entry.key),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: BracuPalette.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...entry.value.asMap().entries.map((itemEntry) {
                      final isTargetCard = isTargetSection && itemEntry.key == 0;
                      if (isTargetCard) {
                        _highlightKey ??= GlobalKey();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CalendarCard(
                          key: isTargetCard ? _highlightKey : null,
                          item: itemEntry.value,
                          isHighlighted: isTargetCard,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }
          final content = BracuRefreshScroll(
            onRefresh: _refresh,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
          if (!_didScroll && _highlightKey != null) {
            attemptScrollToHighlightedKey(
              highlightKey: _highlightKey,
              hasRetried: _scrollRetry,
              alignment: 0.18,
              retry: () {
                _scrollRetry = true;
                if (mounted) {
                  setState(() {});
                }
              },
              onScrolled: () {
                _didScroll = true;
              },
            );
          }
          return content;
        },
      ),
    );
  }

  Map<DateTime, List<CalendarEntry>> _groupByDate(List<CalendarEntry> items) {
    final grouped = <DateTime, List<CalendarEntry>>{};
    for (final item in items) {
      final raw = item.primaryDate.trim();
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      final key = DateTime(parsed.year, parsed.month, parsed.day);
      grouped.putIfAbsent(key, () => <CalendarEntry>[]).add(item);
    }
    return grouped;
  }

  String _dayLabel(DateTime date) {
    return formatRelativeDayLabel(date, includeTomorrow: true);
  }

}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    super.key,
    required this.item,
    this.isHighlighted = false,
  });

  final CalendarEntry item;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final badge = _badgeLabel(item);
    final badgeColor = _badgeColor(item.typeKey);
    final timeLabel = _timeLabel(item);
    final roomLabel = item.roomNumber.isNotEmpty
        ? item.roomNumber
        : item.roomName;
    final trailing = roomLabel.isNotEmpty ? roomLabel : item.place;
    final trailingSub = item.building.isNotEmpty ? item.building : item.sessionLabel;

    return BracuCard(
      key: key,
      isHighlighted: isHighlighted,
      highlightColor: BracuPalette.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label.isEmpty ? 'Untitled Event' : item.label,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.department.isNotEmpty ||
                    item.faculty.isNotEmpty ||
                    item.actor.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.faculty.isNotEmpty) item.faculty,
                      if (item.department.isNotEmpty) item.department,
                      if (item.actor.isNotEmpty) item.actor,
                    ].join(' • '),
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (trailing.trim().isNotEmpty)
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailing,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailingSub.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trailingSub,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _badgeLabel(CalendarEntry item) {
    final key = item.typeKey.toUpperCase();
    if (key.contains('MID')) return 'MID';
    if (key.contains('FINAL')) return 'FIN';
    if (key.contains('CLASS')) return 'CLS';
    if (key.contains('HOLIDAY')) return 'OFF';
    if (key.contains('EXAM')) return 'EXM';
    return key.isEmpty ? 'EVT' : key.substring(0, key.length.clamp(0, 3));
  }

  Color _badgeColor(String key) {
    final upper = key.toUpperCase();
    if (upper.contains('HOLIDAY')) return BracuPalette.danger;
    if (upper.contains('MID') || upper.contains('FINAL') || upper.contains('EXAM')) {
      return BracuPalette.accent;
    }
    if (upper.contains('CLASS')) return BracuPalette.primary;
    return BracuPalette.info;
  }

  String _timeLabel(CalendarEntry item) {
    if (item.startTime.isNotEmpty && item.endTime.isNotEmpty) {
      return '${formatTime(item.startTime)} - ${formatTime(item.endTime)}';
    }
    if (item.startDate.isNotEmpty &&
        item.endDate.isNotEmpty &&
        item.startDate != item.endDate) {
      final start = DateTime.tryParse(item.startDate);
      final end = DateTime.tryParse(item.endDate);
      if (start != null && end != null) {
        return '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(end)}';
      }
    }
    return item.typeKey.replaceAll('_', ' ').trim();
  }
}

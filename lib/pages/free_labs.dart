import 'package:flutter/material.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

class FreeLabsPage extends StatefulWidget {
  const FreeLabsPage({super.key});

  @override
  State<FreeLabsPage> createState() => _FreeLabsPageState();
}

class _FreeLabsPageState extends State<FreeLabsPage> {
  late Future<List<_FreeRoomSlot>> _future;
  List<_FreeRoomSlot> _lastSlots = const <_FreeRoomSlot>[];
  List<_FreeRoomSlot> _lastAllSlots = const <_FreeRoomSlot>[];
  final ScrollController _scrollController = ScrollController();
  GlobalKey? _highlightKey;
  String? _lastHighlightToken;
  bool _didScroll = false;
  bool _scrollRetry = false;
  _RoomFilter _selectedFilter = _RoomFilter.labs;

  @override
  void initState() {
    super.initState();
    _future = _loadSlots();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static String _defaultDay() {
    const byWeekday = <int, String>{
      DateTime.saturday: 'Saturday',
      DateTime.sunday: 'Sunday',
      DateTime.monday: 'Monday',
      DateTime.tuesday: 'Tuesday',
      DateTime.wednesday: 'Wednesday',
      DateTime.thursday: 'Thursday',
    };
    return byWeekday[DateTime.now().weekday] ?? 'Saturday';
  }

  Future<List<_FreeRoomSlot>> _loadSlots({bool forceRefresh = false}) async {
    final allSlots = await _loadAllSlots(forceRefresh: forceRefresh);
    _lastAllSlots = allSlots;
    return _applySelectedFilter(allSlots);
  }

  Future<List<_FreeRoomSlot>> _loadAllSlots({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedSlots = await _readCachedSlots();
      if (cachedSlots.isNotEmpty) return cachedSlots;
    }

    final service = SeatStatusService();
    final details = forceRefresh
        ? await service.fetchAllSectionsDetailsFromApi()
        : await service.loadCachedDetails(
            maxAge: const Duration(days: 30),
          ).then((cached) async {
            if (cached.isNotEmpty) return cached;
            return service.fetchAllSectionsDetailsFromApi();
          });
    final allSlots = _buildFreeRoomSlots(details.values.toList(), _defaultDay());
    await _writeCachedSlots(allSlots);
    return allSlots;
  }

  Future<void> _refresh() async {
    final next = _loadSlots(forceRefresh: true);
    setState(() {
      _future = next;
      _didScroll = false;
      _scrollRetry = false;
    });
    final slots = await next;
    if (!mounted) return;
    setState(() {
      _lastSlots = slots;
    });
  }

  void _attemptScrollToHighlight() {
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

  Future<void> _changeFilter(_RoomFilter selected) async {
    if (selected == _selectedFilter) return;
    final next = _lastAllSlots.isNotEmpty
        ? Future<List<_FreeRoomSlot>>.value(
            _applyFilter(_lastAllSlots, selected),
          )
        : _loadSlots();
    setState(() {
      _selectedFilter = selected;
      _future = next;
      _didScroll = false;
      _scrollRetry = false;
    });
    final slots = await next;
    if (!mounted) return;
    setState(() {
      _lastSlots = slots;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Free Labs',
      subtitle: 'No Schedule',
      icon: Icons.computer_outlined,
      actions: [
        BracuSelectDropdownChip<_RoomFilter>(
          label: _selectedFilter.label,
          icon: switch (_selectedFilter) {
            _RoomFilter.classes => Icons.class_outlined,
            _RoomFilter.labs => Icons.science_outlined,
            _RoomFilter.theater => Icons.theaters_outlined,
          },
          title: 'Choose Filter',
          subtitle: 'Filter free labs by room type',
          selectedValue: _selectedFilter,
          options: const [
            BracuSelectOption<_RoomFilter>(
              value: _RoomFilter.labs,
              label: 'Labs',
              subtitle: 'Computer and lab rooms',
              icon: Icons.science_outlined,
            ),
            BracuSelectOption<_RoomFilter>(
              value: _RoomFilter.classes,
              label: 'Classes',
              subtitle: 'Regular classrooms',
              icon: Icons.class_outlined,
            ),
            BracuSelectOption<_RoomFilter>(
              value: _RoomFilter.theater,
              label: 'Theaters',
              subtitle: 'Lecture theater rooms',
              icon: Icons.theaters_outlined,
            ),
          ],
          onSelected: _changeFilter,
        ),
      ],
      body: FutureBuilder<List<_FreeRoomSlot>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _lastSlots.isEmpty) {
            return buildRefreshLoadingState(
              onRefresh: _refresh,
              label: 'Loading...',
            );
          }

          final slots = snapshot.data ?? _lastSlots;
          final visibleSlots = _visibleRoomSlots(slots);
          if (visibleSlots.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              message: 'No free labs found for ${formatWeekdayTitle(_defaultDay())}.',
            );
          }

          final highlightIndex = _highlightIndex(visibleSlots);
          final highlightedSlot = highlightIndex == null
              ? null
              : visibleSlots[highlightIndex];
          final highlightToken = highlightedSlot == null
              ? null
              : '${highlightedSlot.roomNumber}_${highlightedSlot.startTime}_${highlightedSlot.endTime}';
          final groupedSlots = <String, List<_FreeRoomSlot>>{};
          for (final slot in visibleSlots) {
            final key = '${slot.startTime}|${slot.endTime}';
            groupedSlots.putIfAbsent(key, () => <_FreeRoomSlot>[]).add(slot);
          }
          _highlightKey = null;
          if (highlightToken != null && highlightToken != _lastHighlightToken) {
            _lastHighlightToken = highlightToken;
            _didScroll = false;
            _scrollRetry = false;
          }

          final children = <Widget>[];
          for (final entry in groupedSlots.entries) {
            final timeSlots = entry.value;
            final firstSlot = timeSlots.first;
            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: BracuSectionTitle(
                          title: formatTimeRange(
                            firstSlot.startTime,
                            firstSlot.endTime,
                          ),
                        ),
                      ),
                      Text(
                        _headerDayLabel(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: BracuPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...timeSlots.map((slot) {
                    final slotToken =
                        '${slot.roomNumber}_${slot.startTime}_${slot.endTime}';
                    final isHighlighted = slotToken == highlightToken;
                    final isGreenProgram = _isGreenProgram(slot);
                    if (isHighlighted) {
                      _highlightKey ??= GlobalKey();
                    }
                    final roomSlots = visibleSlots
                        .where((item) => item.roomNumber == slot.roomNumber)
                        .toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showRoomDetails(slot, roomSlots),
                        child: BracuCard(
                          key: isHighlighted ? _highlightKey : null,
                          isHighlighted: isHighlighted || isGreenProgram,
                          highlightColor: _roomCardHighlightColor(slot),
                          backgroundColor: _roomCardBackgroundColor(slot),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: slot.roomNumber,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (slot.statusLabel == 'Available')
                                            TextSpan(
                                              text: ' Free',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    BracuPalette.textSecondary(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatTimeRange(
                                        slot.startTime,
                                        slot.endTime,
                                      ),
                                      style: TextStyle(
                                        color: BracuPalette.textPrimary(context),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text.rich(
                                      _roomProgramLabelSpan(slot),
                                      textAlign: TextAlign.right,
                                    ),
                                    if (slot.statusLabel.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        slot.statusLabel,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: BracuPalette.textSecondary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
              ),
            );
          }

          if (!_didScroll && _highlightKey != null) {
            _attemptScrollToHighlight();
          }

          return BracuRefreshList(
            onRefresh: _refresh,
            controller: _scrollController,
            children: children,
          );
        },
      ),
    );
  }

  int? _highlightIndex(List<_FreeRoomSlot> slots) {
    if (slots.isEmpty) return null;
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final start = _minutesFromString(slot.startTime);
      final end = _minutesFromString(slot.endTime);
      if (start != null && end != null && nowMinutes >= start && nowMinutes < end) {
        return i;
      }
    }
    for (var i = 0; i < slots.length; i++) {
      final start = _minutesFromString(slots[i].startTime);
      if (start != null && nowMinutes < start) return i;
    }
    return 0;
  }

  List<_FreeRoomSlot> _buildFreeRoomSlots(
    List<SeatStatusDetailsResponse> details,
    String day,
  ) {
    final grouped = <String, _RoomSeed>{};
    final seenBusyKeys = <String>{};

    for (final detailsEntry in details) {
      for (final section in _extractRoomSections(detailsEntry)) {
        final roomNumber = section.roomNumber.trim();
        if (roomNumber.isEmpty) continue;
        final room = grouped.putIfAbsent(
          roomNumber,
          () => _RoomSeed(
            roomNumber: roomNumber,
            roomName: section.roomName.trim(),
          ),
        );
        final courseCode = section.courseCode.trim().toUpperCase();
        if (courseCode.isNotEmpty) {
          final program = _courseProgramCode(courseCode);
          if (program.isNotEmpty) {
            room.programCounts[program] = (room.programCounts[program] ?? 0) + 1;
          }
        }
        final courseTitle = section.name.trim();
        if (courseTitle.isNotEmpty && courseCode.isNotEmpty) {
          room.courseTitles.add('$courseTitle ($courseCode)');
        } else if (courseTitle.isNotEmpty) {
          room.courseTitles.add(courseTitle);
        } else {
          final sectionName = section.sectionName.trim();
          final fallback = sectionName.isEmpty
              ? courseCode
              : '$courseCode - $sectionName';
          if (fallback.trim().isNotEmpty) {
            room.courseTitles.add(fallback.trim());
          }
        }
        for (final slot in section.sectionSchedule.classSchedules) {
          if (_normalizeDay(slot.day) != day) continue;
          final key = '$roomNumber|${slot.day}|${slot.startTime}|${slot.endTime}';
          if (!seenBusyKeys.add(key)) continue;
          room.busySlots.add(
            _TimeSlot.fromStrings(
              startTime: slot.startTime,
              endTime: slot.endTime,
            ),
          );
        }
      }
    }

    final slots = <_FreeRoomSlot>[];
    for (final room in grouped.values) {
      final freeSlots = _freeWithinDay(_mergeSlots(room.busySlots));
      for (final free in freeSlots) {
        slots.add(
          _FreeRoomSlot(
            roomNumber: room.roomNumber,
            roomName: room.roomName.isEmpty ? 'Room' : room.roomName,
            courseTitlesLabel: (room.courseTitles.toList()..sort()).join(', '),
            dominantProgramCode: _dominantProgramCode(room),
            startTime: _formatTimeOfDay(free.start),
            endTime: _formatTimeOfDay(free.end),
            statusLabel: _statusLabel(free.start, free.end, day),
          ),
        );
      }
    }

    slots.sort((a, b) {
      final startCompare = (_minutesFromString(a.startTime) ?? 0).compareTo(
        _minutesFromString(b.startTime) ?? 0,
      );
      if (startCompare != 0) return startCompare;
      return a.roomNumber.compareTo(b.roomNumber);
    });
    return slots;
  }

  List<_FreeRoomSlot> _applySelectedFilter(List<_FreeRoomSlot> slots) {
    return _applyFilter(slots, _selectedFilter);
  }

  List<_FreeRoomSlot> _applyFilter(
    List<_FreeRoomSlot> slots,
    _RoomFilter filter,
  ) {
    return slots.where((slot) => _matchesFilter(slot.roomNumber, filter)).toList();
  }

  List<SeatStatusSection> _extractRoomSections(SeatStatusDetailsResponse details) {
    final sections = <SeatStatusSection>[];
    final child = details.childSection;
    if (child != null && _looksLikeRoomSection(child)) {
      sections.add(child);
    }
    final main = details.section;
    if (_looksLikeRoomSection(main)) {
      sections.add(main);
    }
    return sections;
  }

  bool _looksLikeRoomSection(SeatStatusSection section) {
    return section.roomNumber.trim().isNotEmpty || section.roomName.trim().isNotEmpty;
  }

  String _normalizeDay(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  List<_TimeSlot> _mergeSlots(List<_TimeSlot> slots) {
    if (slots.isEmpty) return const <_TimeSlot>[];
    final sorted = [...slots]
      ..sort((a, b) => _minutesOfDay(a.start).compareTo(_minutesOfDay(b.start)));
    final merged = <_TimeSlot>[];
    for (final slot in sorted) {
      if (merged.isEmpty) {
        merged.add(slot);
        continue;
      }
      final last = merged.last;
      if (_minutesOfDay(slot.start) <= _minutesOfDay(last.end)) {
        if (_minutesOfDay(slot.end) > _minutesOfDay(last.end)) {
          merged[merged.length - 1] = _TimeSlot(start: last.start, end: slot.end);
        }
      } else {
        merged.add(slot);
      }
    }
    return merged;
  }

  List<_TimeSlot> _freeWithinDay(List<_TimeSlot> busy) {
    const dayStart = TimeOfDay(hour: 8, minute: 0);
    const dayEnd = TimeOfDay(hour: 20, minute: 0);
    if (busy.isEmpty) {
      return const <_TimeSlot>[_TimeSlot(start: dayStart, end: dayEnd)];
    }
    final free = <_TimeSlot>[];
    var current = dayStart;
    for (final slot in busy) {
      if (_minutesOfDay(current) < _minutesOfDay(slot.start)) {
        free.add(_TimeSlot(start: current, end: slot.start));
      }
      if (_minutesOfDay(slot.end) > _minutesOfDay(current)) {
        current = slot.end;
      }
    }
    if (_minutesOfDay(current) < _minutesOfDay(dayEnd)) {
      free.add(_TimeSlot(start: current, end: dayEnd));
    }
    return free
        .where((slot) => _minutesOfDay(slot.start) < _minutesOfDay(slot.end))
        .toList();
  }

  String _statusLabel(TimeOfDay start, TimeOfDay end, String day) {
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    final startMinutes = _minutesOfDay(start);
    final endMinutes = _minutesOfDay(end);
    if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
      return 'Available';
    }
    if (nowMinutes < startMinutes) {
      return 'Upcoming';
    }
    return '';
  }

  int _minutesOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

  int? _minutesFromString(String value) => BracuTime.toMinutes(value);

  String _todayCacheLabel() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<List<_FreeRoomSlot>> _readCachedSlots() async {
    try {
      final cached = await SeatStatusService().loadCachedFreeLabsSlots(
        dateKey: _todayCacheLabel(),
      );
      return cached.map(_FreeRoomSlot.fromJson).toList();
    } catch (_) {
      return const <_FreeRoomSlot>[];
    }
  }

  Future<void> _writeCachedSlots(List<_FreeRoomSlot> slots) async {
    try {
      await SeatStatusService().saveFreeLabsSlotsCacheIfChanged(
        dateKey: _todayCacheLabel(),
        slots: slots.map((slot) => slot.toJson()).toList(),
      );
    } catch (_) {}
  }

  String _headerDayLabel() {
    final now = DateTime.now();
    return '${formatWeekdayTitle(_defaultDay())}, ${now.day} ${_monthLabel(now.month)}';
  }

  String _monthLabel(int month) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  Future<void> _showRoomDetails(
    _FreeRoomSlot slot,
    List<_FreeRoomSlot> roomSlots,
  ) async {
    final visibleRoomSlots = _visibleRoomSlots(roomSlots);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BracuPalette.card(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final textPrimary = BracuPalette.textPrimary(sheetContext);
        final textSecondary = BracuPalette.textSecondary(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textSecondary.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Text(
                            '${slot.roomNumber} • ${_roomTypeLabel(slot.roomNumber)}',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (_roomHeaderSubtitle(slot).isNotEmpty)
                            Text.rich(
                              _roomHeaderSubtitleSpan(slot, textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: Icon(Icons.close_rounded, color: textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Today',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...visibleRoomSlots.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: BracuCard(
                        isHighlighted: item.statusLabel == 'Available',
                        highlightColor: BracuPalette.primary,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatTimeRange(item.startTime, item.endTime),
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (item.statusLabel.isNotEmpty)
                              Text(
                                item.statusLabel,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_FreeRoomSlot> _visibleRoomSlots(List<_FreeRoomSlot> roomSlots) {
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    final upcoming = roomSlots.where((item) {
      final end = _minutesFromString(item.endTime);
      return end != null && end > nowMinutes;
    }).toList();
    return upcoming.isNotEmpty ? upcoming : roomSlots;
  }

  bool _matchesFilter(String roomNumber, [_RoomFilter? filter]) {
    final suffix = roomNumber.trim().toUpperCase();
    return switch (filter ?? _selectedFilter) {
      _RoomFilter.classes => suffix.endsWith('C'),
      _RoomFilter.labs => suffix.endsWith('L'),
      _RoomFilter.theater => suffix.endsWith('T'),
    };
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final normalizedHour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$normalizedHour:$minute $suffix';
  }

  String _roomHeaderSubtitle(_FreeRoomSlot slot) {
    final parts = <String>[];
    final roomName = slot.roomName.trim();
    if (roomName.isNotEmpty && roomName != slot.roomNumber.trim()) {
      parts.add(roomName);
    }
    final courses = slot.courseTitlesLabel.trim();
    if (courses.isNotEmpty) {
      parts.add(courses);
    }
    return parts.join(' • ');
  }

  String _roomProgramLabel(_FreeRoomSlot slot) {
    final program = slot.dominantProgramCode.trim().toUpperCase();
    if (program.isEmpty) {
      return slot.roomName;
    }
    return program;
  }

  bool _isGreenProgram(_FreeRoomSlot slot) {
    final program = slot.dominantProgramCode.trim().toUpperCase();
    final roomNumber = slot.roomNumber.trim().toUpperCase();
    final isLab = roomNumber.endsWith('L');
    return isLab && (program == 'CSE' || program == 'EEE');
  }

  String _dominantProgramCode(_RoomSeed room) {
    if (room.programCounts.isEmpty) return '';
    final sorted = room.programCounts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });
    return sorted.first.key;
  }

  Color _roomCardHighlightColor(_FreeRoomSlot slot) {
    return _isGreenProgram(slot)
        ? const Color(0xFF22C55E)
        : BracuPalette.primary;
  }

  Color? _roomCardBackgroundColor(_FreeRoomSlot slot) {
    return null;
  }

  TextSpan _roomProgramLabelSpan(_FreeRoomSlot slot) {
    final program = _roomProgramLabel(slot);
    final roomType = _roomTypeShortLabel(slot.roomNumber);
    return TextSpan(
      children: [
        TextSpan(
          text: program,
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (program != slot.roomName && roomType.isNotEmpty)
          TextSpan(
            text: ' $roomType',
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  String _courseProgramCode(String courseCode) {
    final match = RegExp(r'^[A-Z]+').firstMatch(courseCode.trim().toUpperCase());
    return match?.group(0) ?? '';
  }

  String _roomTypeLabel(String roomNumber) {
    final suffix = roomNumber.trim().toUpperCase();
    if (suffix.endsWith('L')) return 'Lab Room';
    if (suffix.endsWith('T')) return 'Theater Room';
    if (suffix.endsWith('C')) return 'Class Room';
    return 'Room';
  }

  String _roomTypeShortLabel(String roomNumber) {
    final suffix = roomNumber.trim().toUpperCase();
    if (suffix.endsWith('L')) return 'Lab';
    if (suffix.endsWith('T')) return 'Theater';
    if (suffix.endsWith('C')) return 'Class';
    return '';
  }

  TextSpan _roomHeaderSubtitleSpan(_FreeRoomSlot slot, Color secondary) {
    final baseStyle = TextStyle(
      color: secondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final codeStyle = baseStyle.copyWith(
      color: BracuPalette.textPrimary(context),
      fontWeight: FontWeight.w800,
    );
    final subtitle = _roomHeaderSubtitle(slot);
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\([^)]*\)');
    var start = 0;
    for (final match in pattern.allMatches(subtitle)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: subtitle.substring(start, match.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: subtitle.substring(match.start, match.end),
          style: codeStyle,
        ),
      );
      start = match.end;
    }
    if (start < subtitle.length) {
      spans.add(TextSpan(text: subtitle.substring(start), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }
}

class _FreeRoomSlot {
  const _FreeRoomSlot({
    required this.roomNumber,
    required this.roomName,
    required this.courseTitlesLabel,
    required this.dominantProgramCode,
    required this.startTime,
    required this.endTime,
    required this.statusLabel,
  });

  factory _FreeRoomSlot.fromJson(Map<String, dynamic> json) {
    return _FreeRoomSlot(
      roomNumber: (json['roomNumber'] as String? ?? '').trim(),
      roomName: (json['roomName'] as String? ?? '').trim(),
      courseTitlesLabel: (json['courseTitlesLabel'] as String? ?? '').trim(),
      dominantProgramCode: (json['dominantProgramCode'] as String? ?? '')
          .trim(),
      startTime: (json['startTime'] as String? ?? '').trim(),
      endTime: (json['endTime'] as String? ?? '').trim(),
      statusLabel: (json['statusLabel'] as String? ?? '').trim(),
    );
  }

  final String roomNumber;
  final String roomName;
  final String courseTitlesLabel;
  final String dominantProgramCode;
  final String startTime;
  final String endTime;
  final String statusLabel;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'roomNumber': roomNumber,
      'roomName': roomName,
      'courseTitlesLabel': courseTitlesLabel,
      'dominantProgramCode': dominantProgramCode,
      'startTime': startTime,
      'endTime': endTime,
      'statusLabel': statusLabel,
    };
  }
}

class _RoomSeed {
  _RoomSeed({
    required this.roomNumber,
    required this.roomName,
  });

  final String roomNumber;
  final String roomName;
  final Map<String, int> programCounts = <String, int>{};
  final List<_TimeSlot> busySlots = <_TimeSlot>[];
  final Set<String> courseTitles = <String>{};
}

class _TimeSlot {
  const _TimeSlot({
    required this.start,
    required this.end,
  });

  _TimeSlot.fromStrings({
    required String startTime,
    required String endTime,
  }) : start = _FreeRoomTime.parse(startTime),
       end = _FreeRoomTime.parse(endTime);

  final TimeOfDay start;
  final TimeOfDay end;
}

class _FreeRoomTime {
  static TimeOfDay parse(String value) {
    final parsed = BracuTime.parseTime(value);
    if (parsed != null) {
      return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
    }
    return const TimeOfDay(hour: 0, minute: 0);
  }
}

enum _RoomFilter {
  classes('Classes'),
  labs('Labs'),
  theater('Theater');

  const _RoomFilter(this.label);

  final String label;
}

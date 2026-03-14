import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';
import 'package:preconnect/tools/time_utils.dart';

class ExamSchedule extends StatefulWidget {
  const ExamSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ExamSchedule> createState() => _ExamScheduleState();
}

class _ExamScheduleState extends State<ExamSchedule> {
  late Future<List<Section>> _future;
  final ScrollController _scrollController = ScrollController();
  GlobalKey? _highlightKey;
  String? _lastHighlightKey;
  bool _didScroll = false;
  bool _scrollRetry = false;

  @override
  void initState() {
    super.initState();
    unawaited(ScheduleService().fetchStudentSchedule());
    _future = _fetchExamSections();
    ExamSchedule.jumpSignal.addListener(_onJumpRequested);
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    ExamSchedule.jumpSignal.removeListener(_onJumpRequested);
    _scrollController.dispose();
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'exam_schedule') {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  void _onJumpRequested() {
    _didScroll = false;
    _scrollRetry = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<Section>> _fetchExamSections({bool forceRefresh = false}) async {
    return ScheduleService().getStudentSections(forceRefresh: forceRefresh);
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    setState(() {
      _didScroll = false;
      _scrollRetry = false;
      _future = _fetchExamSections(forceRefresh: true);
    });
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'exam_schedule');
    }
  }

  String _formatExamDateLabel(String? input) {
    if (input == null || input.trim().isEmpty) return '';
    final raw = input.trim();
    const patterns = <String>[
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'yyyy.MM.dd',
      'dd-MM-yyyy',
      'dd/MM/yyyy',
      'd/M/yyyy',
      'd MMM yyyy',
      'd MMM, yyyy',
      'd-MMM-yyyy',
      'MMM d, yyyy',
    ];

    DateTime? dt;
    for (final pattern in patterns) {
      try {
        dt = DateFormat(pattern).parseStrict(raw);
        break;
      } catch (_) {}
    }
    dt ??= DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('EEEE, d MMMM, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Exam Schedule',
      subtitle: 'Mid & Final Dates',
      icon: Icons.event_note_outlined,
      body: FutureBuilder<List<Section>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return buildRefreshLoadingState(
              onRefresh: _handleRefresh,
              label: 'Loading exams...',
            );
          } else if (snapshot.hasError) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No exam data available',
            );
          }

          final sections = snapshot.data!;
          final midExams = sections
              .where(
                (s) =>
                    s.sectionSchedule.midExamDate != null &&
                    s.sectionSchedule.midExamStartTime != null,
              )
              .toList();
          final finalExams = sections
              .where(
                (s) =>
                    s.sectionSchedule.finalExamDate != null &&
                    s.sectionSchedule.finalExamStartTime != null,
              )
              .toList();

          midExams.sort((a, b) {
            final aTime = BracuTime.parseDateTime(
              a.sectionSchedule.midExamDate,
              a.sectionSchedule.midExamStartTime,
            );
            final bTime = BracuTime.parseDateTime(
              b.sectionSchedule.midExamDate,
              b.sectionSchedule.midExamStartTime,
            );
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

          finalExams.sort((a, b) {
            final aTime = BracuTime.parseDateTime(
              a.sectionSchedule.finalExamDate,
              a.sectionSchedule.finalExamStartTime,
            );
            final bTime = BracuTime.parseDateTime(
              b.sectionSchedule.finalExamDate,
              b.sectionSchedule.finalExamStartTime,
            );
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

          if (midExams.isEmpty && finalExams.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No exams scheduled',
            );
          }

          final now = DateTime.now();
          DateTime? nextExamTime;
          String? nextExamKey;
          DateTime? ongoingExamEnd;
          String? ongoingExamKey;
          for (final s in sections) {
            final midTime = BracuTime.parseDateTime(
              s.sectionSchedule.midExamDate,
              s.sectionSchedule.midExamStartTime,
            );
            final midEndTime = BracuTime.parseDateTime(
              s.sectionSchedule.midExamDate,
              s.sectionSchedule.midExamEndTime,
            );
            if (midTime != null) {
              if (midEndTime != null &&
                  now.isAfter(midTime) &&
                  now.isBefore(midEndTime)) {
                if (ongoingExamEnd == null ||
                    midEndTime.isBefore(ongoingExamEnd)) {
                  ongoingExamEnd = midEndTime;
                  ongoingExamKey = '${s.sectionId}-mid';
                }
              } else if (midTime.isAfter(now)) {
                if (nextExamTime == null || midTime.isBefore(nextExamTime)) {
                  nextExamTime = midTime;
                  nextExamKey = '${s.sectionId}-mid';
                }
              }
            }
            final finalTime = BracuTime.parseDateTime(
              s.sectionSchedule.finalExamDate,
              s.sectionSchedule.finalExamStartTime,
            );
            final finalEndTime = BracuTime.parseDateTime(
              s.sectionSchedule.finalExamDate,
              s.sectionSchedule.finalExamEndTime,
            );
            if (finalTime != null) {
              if (finalEndTime != null &&
                  now.isAfter(finalTime) &&
                  now.isBefore(finalEndTime)) {
                if (ongoingExamEnd == null ||
                    finalEndTime.isBefore(ongoingExamEnd)) {
                  ongoingExamEnd = finalEndTime;
                  ongoingExamKey = '${s.sectionId}-final';
                }
              } else if (finalTime.isAfter(now)) {
                if (nextExamTime == null || finalTime.isBefore(nextExamTime)) {
                  nextExamTime = finalTime;
                  nextExamKey = '${s.sectionId}-final';
                }
              }
            }
          }

          final highlightedKey = ongoingExamKey ?? nextExamKey;

          final children = <Widget>[];
          _highlightKey = null;

          if (midExams.isNotEmpty) {
            children.add(const BracuSectionTitle(title: 'Midterm'));
            children.add(const SizedBox(height: 10));
            children.addAll(
              midExams.map((section) {
                final schedule = section.sectionSchedule;
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-mid';
                if (isHighlighted) {
                  _highlightKey ??= GlobalKey();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatExamDateLabel(schedule.midExamDate),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: BracuPalette.textPrimary(context),
                              ),
                            ),
                          ),
                          Text(
                            'Midterm',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      BracuCard(
                        key: isHighlighted ? _highlightKey : null,
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: Row(
                          children: [
                            SectionBadge(
                              label: formatSectionBadge(section.sectionName),
                              color: BracuPalette.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    section.courseCode,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatTimeRange(
                                      schedule.midExamStartTime,
                                      schedule.midExamEndTime,
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
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
                                  Text(
                                    section.roomNumber.isNotEmpty
                                        ? section.roomNumber
                                        : '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (section.faculties.trim().isNotEmpty &&
                                      section.faculties.trim().toUpperCase() !=
                                          'OTHER') ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      section.faculties,
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
                    ],
                  ),
                );
              }),
            );
            children.add(const SizedBox(height: 6));
          }

          if (finalExams.isNotEmpty) {
            children.add(const BracuSectionTitle(title: 'Final'));
            children.add(const SizedBox(height: 10));
            children.addAll(
              finalExams.map((section) {
                final schedule = section.sectionSchedule;
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-final';
                if (isHighlighted) {
                  _highlightKey ??= GlobalKey();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatExamDateLabel(schedule.finalExamDate),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: BracuPalette.textPrimary(context),
                              ),
                            ),
                          ),
                          Text(
                            'Final',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      BracuCard(
                        key: isHighlighted ? _highlightKey : null,
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: Row(
                          children: [
                            SectionBadge(
                              label: formatSectionBadge(section.sectionName),
                              color: BracuPalette.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    section.courseCode,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatTimeRange(
                                      schedule.finalExamStartTime,
                                      schedule.finalExamEndTime,
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
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
                                  Text(
                                    section.roomNumber.isNotEmpty
                                        ? section.roomNumber
                                        : '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (section.faculties.trim().isNotEmpty &&
                                      section.faculties.trim().toUpperCase() !=
                                          'OTHER') ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      section.faculties,
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
                    ],
                  ),
                );
              }),
            );
          }

          children.add(const SizedBox(height: 8));

          if (highlightedKey != null && highlightedKey != _lastHighlightKey) {
            _lastHighlightKey = highlightedKey;
            _didScroll = false;
            _scrollRetry = false;
          }
          if (!_didScroll && _highlightKey != null) {
            attemptScrollToHighlightedKey(
              highlightKey: _highlightKey,
              hasRetried: _scrollRetry,
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

          return BracuRefreshList(
            onRefresh: _handleRefresh,
            controller: _scrollController,
            children: children,
          );
        },
      ),
    );
  }
}

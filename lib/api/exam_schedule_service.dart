import 'package:preconnect/api/exam_map_service.dart';
import 'package:preconnect/model/exam_schedule_info.dart';
import 'package:preconnect/model/section_info.dart';

class ExamScheduleService {
  ExamScheduleService._internal();
  static final ExamScheduleService _instance = ExamScheduleService._internal();
  factory ExamScheduleService() => _instance;

  Future<Map<String, ExamScheduleOverride>> getOverridesForSections(
    List<Section> sections, {
    bool forceRefresh = false,
    int? forcedSemesterSessionId,
  }) async {
    if (sections.isEmpty) return const <String, ExamScheduleOverride>{};
    final semesterSessionId =
        forcedSemesterSessionId ?? resolveSemesterSessionId(sections);
    if (semesterSessionId == null) {
      return const <String, ExamScheduleOverride>{};
    }
    return ExamMapService().getOverridesForSemester(
      semesterSessionId: semesterSessionId,
      forceRefresh: forceRefresh,
    );
  }

  int? resolveSemesterSessionId(List<Section> sections) {
    if (sections.isEmpty) return null;
    final counts = <int, int>{};
    for (final section in sections) {
      counts.update(
        section.semesterSessionId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    int? selectedId;
    var maxCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        selectedId = entry.key;
      }
    }
    return selectedId;
  }

  ExamSectionResolved resolveSection({
    required Section section,
    required Map<String, ExamScheduleOverride> overrides,
  }) {
    final override = overrides[ExamMapService.sectionKeyForSection(section)];
    final fallbackRoom = section.roomNumber.trim();
    final midRoom = _pickRoom(override?.midRoomNumber, fallbackRoom);
    final finalRoom = _pickRoom(
      override?.finalRoomNumber,
      midRoom.isNotEmpty ? midRoom : fallbackRoom,
    );
    return ExamSectionResolved(
      midDate: override?.midDate ?? section.sectionSchedule.midExamDate,
      midStartTime:
          override?.midStartTime ?? section.sectionSchedule.midExamStartTime,
      midEndTime:
          override?.midEndTime ?? section.sectionSchedule.midExamEndTime,
      midRoomNumber: midRoom,
      finalDate: override?.finalDate ?? section.sectionSchedule.finalExamDate,
      finalStartTime:
          override?.finalStartTime ??
          section.sectionSchedule.finalExamStartTime,
      finalEndTime:
          override?.finalEndTime ?? section.sectionSchedule.finalExamEndTime,
      finalRoomNumber: finalRoom,
    );
  }

  String _pickRoom(String? preferred, String fallback) {
    final selected = (preferred ?? '').trim();
    if (selected.isNotEmpty) return selected;
    return fallback.trim();
  }
}

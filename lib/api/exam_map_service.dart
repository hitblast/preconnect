import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/sembast_cache.dart';
import 'package:preconnect/model/exam_schedule_info.dart';
import 'package:preconnect/model/section_info.dart';

class ExamMapService {
  ExamMapService._internal();
  static final ExamMapService _instance = ExamMapService._internal();
  factory ExamMapService() => _instance;

  final ApiClient _client = ApiClient();
  final SembastCache _cache = SembastCache();

  static const String _indexUrl = 'https://api.preconnect.app/data/exammap';
  static const Duration _indexCacheTtl = Duration(hours: 6);
  static const Duration _examJsonCacheTtl = Duration(hours: 12);

  static String sectionKeyForSection(Section section) {
    return sectionKey(
      courseCode: section.courseCode,
      sectionName: section.sectionName,
    );
  }

  static String sectionKey({
    required String courseCode,
    required String sectionName,
  }) {
    final course = courseCode.trim().toUpperCase();
    final section = _normalizeSection(sectionName);
    if (course.isEmpty || section.isEmpty) return '';
    return '$course|$section';
  }

  Future<Map<String, ExamScheduleOverride>> getOverridesForSemester({
    required int semesterSessionId,
    bool forceRefresh = false,
  }) async {
    final semesterLabel = _semesterLabelFromSessionId(semesterSessionId);
    if (semesterLabel.isEmpty) return const <String, ExamScheduleOverride>{};

    final indexJson = await _fetchJsonWithCache(
      url: _indexUrl,
      cacheKey: 'exammap_index_v1',
      ttl: _indexCacheTtl,
      forceRefresh: forceRefresh,
    );

    final indexList = indexJson is List ? indexJson : const <dynamic>[];
    final midUrl = _pickExamJsonUrl(
      indexList,
      examType: 'Mid',
      semesterLabel: semesterLabel,
    );
    final finalUrl = _pickExamJsonUrl(
      indexList,
      examType: 'Final',
      semesterLabel: semesterLabel,
    );

    final merged = <String, ExamScheduleOverride>{};

    if (midUrl != null) {
      final midJson = await _fetchJsonWithCache(
        url: midUrl,
        cacheKey: 'exammap_mid_${semesterSessionId}_v1',
        ttl: _examJsonCacheTtl,
        forceRefresh: forceRefresh,
      );
      _mergeExamRows(merged, midJson, examTypeHint: 'Mid');
    }

    if (finalUrl != null) {
      final finalJson = await _fetchJsonWithCache(
        url: finalUrl,
        cacheKey: 'exammap_final_${semesterSessionId}_v1',
        ttl: _examJsonCacheTtl,
        forceRefresh: forceRefresh,
      );
      _mergeExamRows(merged, finalJson, examTypeHint: 'Final');
    }

    return merged;
  }

  Future<dynamic> _fetchJsonWithCache({
    required String url,
    required String cacheKey,
    required Duration ttl,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = await _cache.getJsonMap(cacheKey);
      final ts = cached?['ts'];
      final data = cached?['data'];
      if (ts is int && data != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
        if (age <= ttl) return data;
      }
    }

    try {
      final response = await _client.publicGet(url);
      final decoded = jsonDecode(response.body);
      await _cache.setJson(cacheKey, <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': decoded,
      });
      return decoded;
    } catch (_) {
      final cached = await _cache.getJsonMap(cacheKey);
      return cached?['data'];
    }
  }

  void _mergeExamRows(
    Map<String, ExamScheduleOverride> out,
    dynamic payload, {
    required String examTypeHint,
  }) {
    if (payload is! Map<String, dynamic>) return;

    final metadata = payload['metadata'];
    final metaType = metadata is Map<String, dynamic>
        ? _clean(metadata['exam_type'])
        : null;
    final examType = ((metaType ?? examTypeHint).trim().toUpperCase());

    final rows = payload['exams'];
    if (rows is! List) return;

    for (final raw in rows.whereType<Map>()) {
      final row = raw.cast<String, dynamic>();
      final course = _clean(row['Course']).toUpperCase();
      final section = _normalizeSection(_clean(row['Section']));
      if (course.isEmpty || section.isEmpty) continue;
      final key = '$course|$section';

      final date = _clean(row['Mid Date']).isNotEmpty
          ? _clean(row['Mid Date'])
          : _clean(row['Final Date']);
      final start = _clean(row['Start Time']);
      final end = _clean(row['End Time']);
      final room = _clean(row['Room.']);

      final existing = out[key] ?? const ExamScheduleOverride();

      if (examType == 'MID') {
        out[key] = existing.copyWith(
          midDate: date.isEmpty ? existing.midDate : date,
          midStartTime: start.isEmpty ? existing.midStartTime : start,
          midEndTime: end.isEmpty ? existing.midEndTime : end,
          midRoomNumber: room.isEmpty ? existing.midRoomNumber : room,
        );
      } else {
        out[key] = existing.copyWith(
          finalDate: date.isEmpty ? existing.finalDate : date,
          finalStartTime: start.isEmpty ? existing.finalStartTime : start,
          finalEndTime: end.isEmpty ? existing.finalEndTime : end,
          finalRoomNumber: room.isEmpty ? existing.finalRoomNumber : room,
        );
      }
    }
  }

  String _semesterLabelFromSessionId(int sessionId) {
    final year = sessionId ~/ 10;
    final code = sessionId % 10;
    final term = switch (code) {
      1 => 'Spring',
      2 => 'Summer',
      3 => 'Fall',
      _ => '',
    };
    if (term.isEmpty) return '';
    return '$term $year';
  }

  String? _pickExamJsonUrl(
    List<dynamic> indexRows, {
    required String examType,
    required String semesterLabel,
  }) {
    final wanted = '$examType $semesterLabel'.toLowerCase();

    for (final item in indexRows.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final name = _clean(row['exam_name']).toLowerCase();
      final url = _clean(row['url']);
      if (name == wanted && url.isNotEmpty) return url;
    }

    for (final item in indexRows.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final name = _clean(row['exam_name']).toLowerCase();
      final url = _clean(row['url']);
      if (url.isEmpty) continue;
      if (name.contains(examType.toLowerCase()) &&
          name.contains(semesterLabel.toLowerCase())) {
        return url;
      }
    }

    return null;
  }

  static String _clean(dynamic value) => value?.toString().trim() ?? '';

  static String _normalizeSection(String raw) {
    final match = RegExp(r'\d+').firstMatch(raw.trim());
    if (match == null) return '';
    final parsed = int.tryParse(match.group(0)!);
    if (parsed == null) return match.group(0)!;
    return parsed.toString();
  }
}

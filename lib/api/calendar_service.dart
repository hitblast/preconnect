import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/calendar_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalendarService {
  CalendarService._internal();
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'calendar_feed_json';
  static const String _rangeStartKey = 'calendar_range_start';
  static const String _rangeEndKey = 'calendar_range_end';
  static const String _sourceFingerprintKey = 'calendar_source_fingerprint';

  Future<CalendarFeed?> getCalendar() async {
    final range = await _resolveRange();
    final cached = await _readCache();
    if (cached != null &&
        cached.rangeStart == range.startDate &&
        cached.rangeEnd == range.endDate &&
        cached.sourceFingerprint == range.sourceFingerprint) {
      return cached;
    }
    return fetchCalendar(fallback: cached, rangeOverride: range);
  }

  Future<CalendarFeed?> fetchCalendar({
    CalendarFeed? fallback,
    ({String startDate, String endDate, String sourceFingerprint})? rangeOverride,
  }) async {
    final range = rangeOverride ?? await _resolveRange();
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.calendarPath(0, startDate: range.startDate, endDate: range.endDate)}';
    if (!await _client.hasConnection()) {
      return fallback ?? await _readCache();
    }
    try {
      final response = await _client.authenticatedGet(url);
      final decoded = jsonDecode(response.body);
      final feed = CalendarFeed(
        rangeStart: range.startDate,
        rangeEnd: range.endDate,
        sourceFingerprint: range.sourceFingerprint,
        items: _parseEntries(decoded),
      );
      await _writeCache(feed);
      return feed;
    } catch (_) {
      return fallback ?? await _readCache();
    }
  }

  Future<({String startDate, String endDate, String sourceFingerprint})>
  _resolveRange() async {
    final scheduleService = ScheduleService();
    var scheduleJson = await scheduleService.getStudentSchedule(fromFetch: true);
    scheduleJson ??= await scheduleService.fetchStudentSchedule(fromGet: true);
    final sections = scheduleService.parseStudentSections(scheduleJson);

    final dates = <DateTime>[];
    for (final section in sections) {
      final start = DateTime.tryParse(section.sectionSchedule.classStartDate.trim());
      final end = DateTime.tryParse(section.sectionSchedule.classEndDate.trim());
      final midExamDate = DateTime.tryParse(
        (section.sectionSchedule.midExamDate ?? '').trim(),
      );
      final finalExamDate = DateTime.tryParse(
        (section.sectionSchedule.finalExamDate ?? '').trim(),
      );
      if (start != null) dates.add(start);
      if (end != null) dates.add(end);
      if (midExamDate != null) dates.add(midExamDate);
      if (finalExamDate != null) dates.add(finalExamDate);
    }

    dates.sort();
    final now = DateTime.now();
    final start = dates.isEmpty
        ? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 14))
        : dates.first;
    final end = dates.isEmpty
        ? DateTime(now.year, now.month, now.day).add(const Duration(days: 60))
        : dates.last;
    final formatter = DateFormat('yyyy-MM-dd');
    return (
      startDate: formatter.format(start),
      endDate: formatter.format(end),
      sourceFingerprint: _fingerprint(scheduleJson),
    );
  }

  String _fingerprint(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toUnsigned(32).toRadixString(16);
  }

  Future<CalendarFeed?> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final feed = CalendarFeed.fromJson(decoded);
      final start = prefs.getString(_rangeStartKey) ?? feed.rangeStart;
      final end = prefs.getString(_rangeEndKey) ?? feed.rangeEnd;
      final fingerprint =
          prefs.getString(_sourceFingerprintKey) ?? feed.sourceFingerprint;
      return CalendarFeed(
        rangeStart: start,
        rangeEnd: end,
        sourceFingerprint: fingerprint,
        items: feed.items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(CalendarFeed feed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(feed.toJson()));
    await prefs.setString(_rangeStartKey, feed.rangeStart);
    await prefs.setString(_rangeEndKey, feed.rangeEnd);
    await prefs.setString(_sourceFingerprintKey, feed.sourceFingerprint);
  }

  List<CalendarEntry> _parseEntries(dynamic raw) {
    final output = <CalendarEntry>[];

    void absorb(dynamic value) {
      if (value is List) {
        for (final item in value) {
          absorb(item);
        }
        return;
      }
      if (value is! Map) return;
      final map = value.cast<dynamic, dynamic>();
      final actor = (map['actor'] ?? '').toString().trim();
      final scheduleInfos = map['scheduleInfos'];
      if (scheduleInfos is List) {
        for (final item in scheduleInfos.whereType<Map>()) {
          final info = item.cast<dynamic, dynamic>();
          final metaData = info['metaData'];
          final meta = <String, String>{};
          if (metaData is List) {
            for (final entry in metaData.whereType<Map>()) {
              final key = (entry['key'] ?? '').toString().trim();
              final value = (entry['value'] ?? '').toString().trim();
              if (key.isNotEmpty) meta[key] = value;
            }
          }
          output.add(
            CalendarEntry(
              id: (info['id'] ?? '').toString().trim(),
              label: (info['label'] ?? '').toString().trim(),
              typeKey: (info['refKey'] ?? '').toString().trim(),
              date: (info['date'] ?? '').toString().trim(),
              startDate: (info['date'] ?? '').toString().trim(),
              endDate: (info['date'] ?? '').toString().trim(),
              startTime: (info['startTime'] ?? '').toString().trim(),
              endTime: (info['endTime'] ?? '').toString().trim(),
              place: (info['place'] ?? '').toString().trim(),
              isRepeatable: info['isRepeatable'] == true,
              isCancelled: info['isCancel'] == true,
              ref: (info['ref'] ?? '').toString().trim(),
              roomName: meta['roomName'] ?? '',
              roomNumber: meta['roomNumber'] ?? '',
              sessionLabel: meta['session'] ?? '',
              building: meta['building'] ?? '',
              faculty: meta['faculty'] ?? '',
              department: meta['department'] ?? '',
              actor: actor,
            ),
          );
        }
        return;
      }

      output.add(
        CalendarEntry(
          id: (map['id'] ?? '').toString().trim(),
          label: (map['label'] ?? '').toString().trim(),
          typeKey: (map['refKey'] ?? 'HOLIDAY').toString().trim(),
          date: '',
          startDate: (map['startDate'] ?? '').toString().trim(),
          endDate: (map['endDate'] ?? '').toString().trim(),
          startTime: (map['startTime'] ?? '').toString().trim(),
          endTime: (map['endTime'] ?? '').toString().trim(),
          place: (map['place'] ?? '').toString().trim(),
          isRepeatable: map['isRepeatable'] == true,
          isCancelled: map['isCancel'] == true,
          ref: (map['ref'] ?? '').toString().trim(),
          roomName: '',
          roomNumber: '',
          sessionLabel: '',
          building: '',
          faculty: '',
          department: '',
          actor: (map['actor'] ?? '').toString().trim(),
        ),
      );
    }

    absorb(raw);
    final filtered = _filterClassSchedulesDuringExamWindows(output);
    filtered.sort((a, b) {
      final dateCmp = a.primaryDate.compareTo(b.primaryDate);
      if (dateCmp != 0) return dateCmp;
      final timeCmp = a.startTime.compareTo(b.startTime);
      if (timeCmp != 0) return timeCmp;
      return a.label.compareTo(b.label);
    });
    return filtered;
  }

  List<CalendarEntry> _filterClassSchedulesDuringExamWindows(
    List<CalendarEntry> entries,
  ) {
    ({String start, String end})? buildWindow(String token) {
      final dates = entries
          .where((item) => item.typeKey.toUpperCase().contains(token))
          .map((item) => item.primaryDate)
          .where((date) => date.trim().isNotEmpty)
          .toList()
        ..sort();
      if (dates.isEmpty) return null;
      return (start: dates.first, end: dates.last);
    }

    final midWindow = buildWindow('MID');
    final finalWindow = buildWindow('FINAL');

    bool insideWindow(String date, ({String start, String end})? window) {
      if (window == null || date.trim().isEmpty) return false;
      return date.compareTo(window.start) >= 0 && date.compareTo(window.end) <= 0;
    }

    return entries.where((item) {
      final typeKey = item.typeKey.toUpperCase();
      if (!typeKey.contains('CLASS_SCHEDULE')) return true;
      final date = item.primaryDate;
      if (insideWindow(date, midWindow)) return false;
      if (insideWindow(date, finalWindow)) return false;
      return true;
    }).toList();
  }
}

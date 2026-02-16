import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/tools/time_utils.dart';

class RamadanTiming {
  RamadanTiming._();

  static const String _statusUrl = 'https://ramadan.munafio.com/api/check';
  static const Duration _requestTimeout = Duration(seconds: 2);
  static const Duration _cacheTtl = Duration(hours: 6);

  static DateTime? _lastCheckAt;
  static bool? _cachedIsRamadan;
  static Future<bool>? _inflight;

  // Based on BRACU Ramadan class timing announcement (2026).
  static const Map<String, (int start, int end)> _ramadanSlots = {
    '480-560': (480, 545),
    '570-650': (555, 620),
    '660-740': (630, 695),
    '750-830': (705, 770),
    '840-920': (780, 845),
    '930-1010': (855, 920),
    '1020-1100': (930, 995),
    '1110-1290': (960, 1080),
  };

  static Future<bool> isRamadan({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final hasFreshCache =
        !forceRefresh &&
        _cachedIsRamadan != null &&
        _lastCheckAt != null &&
        now.difference(_lastCheckAt!) <= _cacheTtl;

    if (hasFreshCache) {
      return _cachedIsRamadan!;
    }

    if (_inflight != null) {
      return _inflight!;
    }

    _inflight = _fetchIsRamadan();
    try {
      final value = await _inflight!;
      _cachedIsRamadan = value;
      _lastCheckAt = now;
      return value;
    } finally {
      _inflight = null;
    }
  }

  static Future<bool> _fetchIsRamadan() async {
    try {
      final response = await http
          .get(
            Uri.parse(_statusUrl),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return _cachedIsRamadan ?? false;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return _cachedIsRamadan ?? false;
      }

      final data = payload['data'];
      if (data is! Map<String, dynamic>) {
        return _cachedIsRamadan ?? false;
      }

      final value = data['isRamadan'];
      if (value is bool) {
        return value;
      }

      return _cachedIsRamadan ?? false;
    } catch (_) {
      return _cachedIsRamadan ?? false;
    }
  }

  static ({String startTime, String endTime, bool adjusted}) adjustRange(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    if (!isRamadan) {
      return (startTime: startTime, endTime: endTime, adjusted: false);
    }

    final startMinutes = BracuTime.toMinutes(startTime);
    final endMinutes = BracuTime.toMinutes(endTime);
    if (startMinutes == null || endMinutes == null) {
      return (startTime: startTime, endTime: endTime, adjusted: false);
    }

    final key = '$startMinutes-$endMinutes';
    final mapped = _ramadanSlots[key];
    if (mapped == null) {
      return (startTime: startTime, endTime: endTime, adjusted: false);
    }

    return (
      startTime: _minutesTo24h(mapped.$1),
      endTime: _minutesTo24h(mapped.$2),
      adjusted: true,
    );
  }

  static int effectiveStartMinutes(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    final adjusted = adjustRange(startTime, endTime, isRamadan: isRamadan);
    return BracuTime.toMinutes(adjusted.startTime) ?? 0;
  }

  static int effectiveEndMinutes(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    final adjusted = adjustRange(startTime, endTime, isRamadan: isRamadan);
    return BracuTime.toMinutes(adjusted.endTime) ?? 0;
  }

  static String _minutesTo24h(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

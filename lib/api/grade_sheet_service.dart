import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/prefs_cache_utils.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GradeSheetFile {
  const GradeSheetFile({required this.file, required this.fromCache});

  final File file;
  final bool fromCache;
}

class GradeSheetService {
  GradeSheetService._internal();
  static final GradeSheetService _instance = GradeSheetService._internal();
  factory GradeSheetService() => _instance;

  final ApiClient _client = ApiClient();
  final Map<String, Future<GradeSheetFile?>> _inFlight =
      <String, Future<GradeSheetFile?>>{};

  Future<GradeSheetFile?> fetchGradeSheet({bool fromGet = false}) async {
    final key = 'gradesheet|$fromGet';
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final request = _fetchGradeSheetInternal(fromGet: fromGet);
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<GradeSheetFile?> _fetchGradeSheetInternal({
    required bool fromGet,
  }) async {
    final prefs = SharedPreferencesAsync();
    final profileId = await resolvePortfolioId(
      prefs: prefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );

    if (profileId == null || profileId.isEmpty) {
      return fromGet ? null : getGradeSheet(fromFetch: true);
    }

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.gradeSheetPath(profileId)}',
        additionalHeaders: const <String, String>{
          'Accept': 'application/pdf, text/plain, */*',
        },
      );
      final bytes = _extractPdfBytes(response.bodyBytes, response.body);
      if (bytes == null || bytes.isEmpty) {
        return fromGet ? null : getGradeSheet(fromFetch: true);
      }

      final file = await _writePdfFile(profileId, bytes);
      return GradeSheetFile(file: file, fromCache: false);
    } catch (_) {
      return fromGet ? null : getGradeSheet(fromFetch: true);
    }
  }

  Future<GradeSheetFile?> getGradeSheet({bool fromFetch = false}) async {
    final prefs = SharedPreferencesAsync();
    final profileId = await resolvePortfolioId(
      prefs: prefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (profileId == null || profileId.isEmpty) return null;

    final file = await _gradeSheetFile(profileId);
    if (await file.exists()) {
      return GradeSheetFile(file: file, fromCache: true);
    }

    if (fromFetch) return null;
    return fetchGradeSheet(fromGet: true);
  }

  Future<File> _writePdfFile(String profileId, Uint8List bytes) async {
    final file = await _gradeSheetFile(profileId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _gradeSheetFile(String profileId) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/grade_sheet_$profileId.pdf');
  }

  Uint8List? _extractPdfBytes(Uint8List rawBytes, String rawBody) {
    if (_looksLikePdf(rawBytes)) {
      return rawBytes;
    }

    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return null;

    final normalized = _normalizeBase64Payload(trimmed);
    if (normalized.isEmpty) return null;

    try {
      final decoded = base64Decode(normalized);
      if (_looksLikePdf(decoded)) {
        return Uint8List.fromList(decoded);
      }
    } catch (_) {}

    return null;
  }

  bool _looksLikePdf(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  String _normalizeBase64Payload(String value) {
    var output = value;
    if (output.startsWith('"') && output.endsWith('"') && output.length >= 2) {
      try {
        output = jsonDecode(output) as String;
      } catch (_) {
        output = output.substring(1, output.length - 1);
      }
    }
    if (output.startsWith('data:')) {
      final commaIndex = output.indexOf(',');
      if (commaIndex >= 0) {
        output = output.substring(commaIndex + 1);
      }
    }
    return output.replaceAll(RegExp(r'\s+'), '');
  }
}

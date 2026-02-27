import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/http_cache_utils.dart';
import 'package:preconnect/api/prefs_cache_utils.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/model/progress_info.dart';

class ProgressService {
  ProgressService._internal();
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;

  static const String _cacheKey = 'StudentProgramProgress';
  static const String _summaryCacheKey = 'StudentProgramProgressSummary';
  static const String _majorMinorsCacheKey =
      'StudentProgramProgressMajorMinors';
  static const String _completedCoursesCacheKey =
      'StudentProgramProgressCompletedCourses';
  static const String _curriculumCacheKey = 'StudentProgramProgressCurriculum';
  static const String _majorMinorsEtagKey = 'StudentProgramProgressMajorEtag';
  static const String _completedCoursesEtagKey =
      'StudentProgramProgressCompletedEtag';
  static const String _curriculumEtagKey = 'StudentProgramProgressCurrEtag';
  final ApiClient _client = ApiClient();
  final Map<String, Future<ProgressInfo?>> _fetchInFlight =
      <String, Future<ProgressInfo?>>{};

  Future<ProgressInfo?> fetchProgress({bool fromGet = false}) async {
    final inFlightKey = 'progress|$fromGet';
    final inFlight = _fetchInFlight[inFlightKey];
    if (inFlight != null) {
      return await inFlight;
    }
    final request = _fetchProgressInternal(fromGet: fromGet);
    _fetchInFlight[inFlightKey] = request;
    try {
      return await request;
    } finally {
      _fetchInFlight.remove(inFlightKey);
    }
  }

  Future<ProgressInfo?> _fetchProgressInternal({required bool fromGet}) async {
    final asyncPrefs = SharedPreferencesAsync();
    final portfolioId = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );

    if (portfolioId == null || portfolioId.isEmpty) {
      if (fromGet) return null;
      return getProgress(fromFetch: true);
    }

    if (!await _client.hasConnection()) {
      return fromGet ? null : getProgress(fromFetch: true);
    }

    try {
      final majorMinorsUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.majorMinorsPath(portfolioId)}';
      final completedCoursesUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.completedCoursesPath(portfolioId)}';
      final curriculumUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.programCurriculumsPath(portfolioId)}';

      final majorEtag = await asyncPrefs.getString(_majorMinorsEtagKey);
      final completedEtag = await asyncPrefs.getString(
        _completedCoursesEtagKey,
      );
      final curriculumEtag = await asyncPrefs.getString(_curriculumEtagKey);

      final responses = await Future.wait([
        _client.authenticatedGet(
          majorMinorsUrl,
          additionalHeaders: ifNoneMatchHeader(majorEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
        _client.authenticatedGet(
          completedCoursesUrl,
          additionalHeaders: ifNoneMatchHeader(completedEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
        _client.authenticatedGet(
          curriculumUrl,
          additionalHeaders: ifNoneMatchHeader(curriculumEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
      ]);

      final majorMinors = await _resolveComponent(
        prefs: asyncPrefs,
        response: responses[0],
        dataKey: _majorMinorsCacheKey,
        etagKey: _majorMinorsEtagKey,
      );
      final completedCourses = await _resolveComponent(
        prefs: asyncPrefs,
        response: responses[1],
        dataKey: _completedCoursesCacheKey,
        etagKey: _completedCoursesEtagKey,
      );
      final curriculum = await _resolveComponent(
        prefs: asyncPrefs,
        response: responses[2],
        dataKey: _curriculumCacheKey,
        etagKey: _curriculumEtagKey,
      );

      if (majorMinors == null ||
          completedCourses == null ||
          curriculum == null) {
        if (fromGet) return null;
        return getProgress(fromFetch: true);
      }

      final payload = <String, dynamic>{
        'majorMinors': majorMinors,
        'completedCourses': completedCourses,
        'curriculum': curriculum,
      };
      final info = ProgressInfo.fromPayload(payload);
      final summary = ProgressSummary.fromProgressInfo(info);
      await writeJsonToPrefs(asyncPrefs, _cacheKey, payload);
      await writeJsonToPrefs(asyncPrefs, _summaryCacheKey, summary.toJson());
      return info;
    } catch (_) {
      if (fromGet) return null;
      return getProgress(fromFetch: true);
    }
  }

  Future<dynamic> _resolveComponent({
    required SharedPreferencesAsync prefs,
    required dynamic response,
    required String dataKey,
    required String etagKey,
  }) async {
    if (response.statusCode == 304) {
      final cached = await prefs.getString(dataKey);
      if (cached == null || cached.trim().isEmpty) return null;
      return jsonDecode(cached);
    }
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    await writeJsonToPrefs(prefs, dataKey, decoded);
    final etag = extractEtagFromHeaders(response.headers);
    if (etag != null && etag.isNotEmpty) {
      await prefs.setString(etagKey, etag);
    }
    return decoded;
  }

  Future<ProgressInfo?> getProgress({bool fromFetch = false}) async {
    final cached = await readCachedStringWithFallback(
      key: _cacheKey,
      fromFetch: fromFetch,
      onCacheMiss: () async {
        final fetched = await fetchProgress(fromGet: true);
        if (fetched == null) return null;
        final asyncPrefs = SharedPreferencesAsync();
        final raw = await asyncPrefs.getString(_cacheKey);
        return raw;
      },
    );
    if (cached == null || cached.isEmpty) {
      return null;
    }

    try {
      final payload = jsonDecode(cached);
      if (payload is! Map<String, dynamic>) {
        if (fromFetch) return null;
        return fetchProgress(fromGet: true);
      }
      return ProgressInfo.fromPayload(payload);
    } catch (_) {
      if (fromFetch) return null;
      return fetchProgress(fromGet: true);
    }
  }

  Future<ProgressSummary?> getProgressSummary({bool fromFetch = false}) async {
    final cached = await readCachedStringWithFallback(
      key: _summaryCacheKey,
      fromFetch: fromFetch,
      onCacheMiss: () async {
        await fetchProgress(fromGet: true);
        final asyncPrefs = SharedPreferencesAsync();
        return await asyncPrefs.getString(_summaryCacheKey);
      },
    );
    if (cached == null || cached.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map<String, dynamic>) return null;
      return ProgressSummary.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

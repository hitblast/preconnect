import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/prefs_cache_utils.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/sembast_cache.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'attendance';

  Future<String?> fetchAttendanceInfo({bool fromGet = false}) async {
    final asyncPrefs = SharedPreferencesAsync();
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getAttendanceInfo(fromFetch: true);
    }

    final url = '${ApiConfig.connectApiBase}${ApiConfig.attendancePath(id)}';

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        await SembastCache().setString(_cacheKey, response.body);
      },
      readCache: ({required bool fromFetch}) =>
          getAttendanceInfo(fromFetch: fromFetch),
    );
  }

  Future<String?> getAttendanceInfo({bool fromFetch = false}) async {
    return readCachedSembastStringWithFallback(
      key: _cacheKey,
      fromFetch: fromFetch,
      onCacheMiss: () => fetchAttendanceInfo(fromGet: true),
    );
  }
}

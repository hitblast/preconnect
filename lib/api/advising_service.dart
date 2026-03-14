import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/sembast_cache.dart';

class AdvisingService {
  static final AdvisingService _instance = AdvisingService._internal();
  factory AdvisingService() => _instance;
  AdvisingService._internal();

  final ApiClient _client = ApiClient();

  static const List<String> cacheKeys = [
    'advisingStartDate',
    'advisingEndDate',
    'activeSemesterSessionId',
    'advisingPhase',
    'totalCredit',
    'earnedCredit',
    'noOfSemester',
  ];

  Future<Map<String, String?>?> fetchAdvisingInfo({
    bool fromGet = false,
  }) async {
    final asyncPrefs = SharedPreferencesAsync();
    final String? studentId = await asyncPrefs.getString('studentId');
    if (studentId == null || studentId.isEmpty) {
      if (fromGet) return null;
      return getAdvisingInfo(fromFetch: true);
    }

    final url = ApiConfig.advisingUrl(studentId);

    return _client.fetchWithFallback<Map<String, String?>>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body)[0];
        await SembastCache().setStringMap(<String, String>{
          'advisingStartDate': '${data['startDate'] ?? ''}',
          'advisingEndDate': '${data['endDate'] ?? ''}',
          'activeSemesterSessionId': '${data['activeSemesterSessionId'] ?? ''}',
          'advisingPhase': '${data['advisingPhase'] ?? ''}',
          'totalCredit': '${data['totalCredit'] ?? ''}',
          'earnedCredit': '${data['earnedCredit'] ?? ''}',
          'noOfSemester': '${data['noOfSemester'] ?? ''}',
        });
      },
      readCache: ({required bool fromFetch}) =>
          getAdvisingInfo(fromFetch: fromFetch),
    );
  }

  Future<Map<String, String?>?> getAdvisingInfo({
    bool fromFetch = false,
  }) async {
    final data = await SembastCache().getStringMap(cacheKeys.toSet());
    final isIncomplete = data.values.any((value) => value == null || value == '');
    if (isIncomplete) {
      if (fromFetch) return null;
      return fetchAdvisingInfo(fromGet: true);
    }
    return data;
  }
}

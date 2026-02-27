import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/prefs_cache_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String?> fetchJsonStringWithFallback({
  required ApiClient client,
  required String url,
  required bool fromGet,
  required SharedPreferencesAsync prefs,
  required String cacheKey,
  required Future<String?> Function({required bool fromFetch}) readCache,
}) {
  return client.fetchWithFallback<String>(
    url: url,
    fromGet: fromGet,
    cacheResponse: (response) async {
      final data = jsonDecode(response.body);
      await writeJsonToPrefs(prefs, cacheKey, data);
    },
    readCache: readCache,
  );
}

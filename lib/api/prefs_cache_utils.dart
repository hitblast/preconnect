import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

Future<void> writeJsonToPrefs(
  SharedPreferencesAsync prefs,
  String key,
  dynamic value,
) async {
  await prefs.setString(key, jsonEncode(value));
}

Future<String?> readCachedStringWithFallback({
  required String key,
  required bool fromFetch,
  required Future<String?> Function() onCacheMiss,
}) async {
  final prefsWithCache = await SharedPreferencesWithCache.create(
    cacheOptions: SharedPreferencesWithCacheOptions(
      allowList: <String>{key},
    ),
  );

  if (fromFetch) await prefsWithCache.reloadCache();

  final cached = prefsWithCache.getString(key) ?? '';
  if (cached.isEmpty) {
    if (fromFetch) return null;
    return onCacheMiss();
  }
  return cached;
}

Future<String?> resolvePortfolioId({
  required SharedPreferencesAsync prefs,
  required Future<void> Function() refreshProfile,
}) async {
  var id = await prefs.getString('id');
  if (id == null || id.isEmpty) {
    await refreshProfile();
    id = await prefs.getString('id');
  }
  if (id == null || id.isEmpty) return null;
  return id;
}

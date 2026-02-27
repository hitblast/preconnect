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
    cacheOptions: SharedPreferencesWithCacheOptions(allowList: <String>{key}),
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

Future<void> writeStringMap(
  SharedPreferencesAsync prefs,
  Map<String, String> values,
) async {
  for (final entry in values.entries) {
    await prefs.setString(entry.key, entry.value);
  }
}

Future<Map<String, String?>?> readRequiredStringMapWithFallback({
  required Set<String> keys,
  required bool fromFetch,
  required Future<Map<String, String?>?> Function() onCacheMiss,
}) async {
  final prefsWithCache = await SharedPreferencesWithCache.create(
    cacheOptions: SharedPreferencesWithCacheOptions(allowList: keys),
  );

  if (fromFetch) await prefsWithCache.reloadCache();

  final data = <String, String?>{};
  for (final key in keys) {
    data[key] = prefsWithCache.getString(key);
  }

  final isIncomplete = data.values.any((value) => value == null || value == '');
  if (isIncomplete) {
    if (fromFetch) return null;
    return onCacheMiss();
  }
  return data;
}

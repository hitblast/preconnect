import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/http_cache_utils.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatStatusService {
  SeatStatusService._internal();

  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  Database? _db;
  Map<int, int>? _seatMapSnapshot;
  final ApiClient _client = ApiClient();

  static const String _dbName = 'seat_status_cache.db';
  static const String _detailsTsKey = 'details_ts';
  static const String _seatMapTsKey = 'seat_map_ts';
  static const String _seatMapEtagKey = 'seat_map_etag';
  static const String _detailsEtagPrefix = 'details_etag_';
  static const String _legacyCleanupDoneKey = 'seat_status_sp_cleanup_done_v1';
  static const List<String> _legacySharedPrefsKeys = <String>[
    'seat_status_details_cache_v1',
    'seat_status_details_cache_ts_v1',
    'seat_status_map_cache_v1',
    'seat_status_map_cache_ts_v1',
  ];

  final StoreRef<String, Object?> _metaStore = StoreRef<String, Object?>(
    'seat_status_meta',
  );
  final StoreRef<int, Object?> _seatMapStore = intMapStoreFactory.store(
    'seat_status_map',
  );
  final StoreRef<int, Object?> _detailsStore = intMapStoreFactory.store(
    'seat_status_details',
  );

  Future<Map<int, int>> loadCachedSeatMap({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final db = await _openDb();
      final ts = await _metaStore.record(_seatMapTsKey).get(db) as int?;
      if (ts == null) return const <int, int>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, int>{};
      final snapshots = await _seatMapStore.find(db);
      if (snapshots.isEmpty) return const <int, int>{};
      final result = <int, int>{};
      for (final snap in snapshots) {
        final value = snap.value;
        if (value is int) {
          result[snap.key] = value;
        } else {
          final parsed = int.tryParse('$value');
          if (parsed != null) {
            result[snap.key] = parsed;
          }
        }
      }
      return result;
    } catch (_) {
      return const <int, int>{};
    }
  }

  Future<Map<int, SeatStatusDetailsResponse>> loadCachedDetails({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final db = await _openDb();
      final ts = await _metaStore.record(_detailsTsKey).get(db) as int?;
      if (ts == null) return const <int, SeatStatusDetailsResponse>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, SeatStatusDetailsResponse>{};
      final snapshots = await _detailsStore.find(db);
      if (snapshots.isEmpty) return const <int, SeatStatusDetailsResponse>{};
      final raw = <String, dynamic>{};
      for (final snap in snapshots) {
        if (snap.value is Map<String, dynamic>) {
          raw[snap.key.toString()] = snap.value;
        } else if (snap.value is Map) {
          raw[snap.key.toString()] = (snap.value as Map)
              .cast<String, dynamic>();
        }
      }
      return _parseCachedDetailsFromMap(raw);
    } catch (_) {
      return const <int, SeatStatusDetailsResponse>{};
    }
  }

  Future<Map<int, int>> replaceSeatMapSnapshotAndSave(
    Map<int, int> fullSeatMap,
  ) async {
    try {
      final db = await _openDb();
      final existing = await _getSeatMapSnapshot(db);

      final changed = <MapEntry<int, int>>[];
      for (final entry in fullSeatMap.entries) {
        if (existing[entry.key] != entry.value) {
          changed.add(entry);
        }
      }
      final removed = existing.keys
          .where((key) => !fullSeatMap.containsKey(key))
          .toList();

      if (changed.isEmpty && removed.isEmpty) {
        _seatMapSnapshot = Map<int, int>.from(fullSeatMap);
        return Map<int, int>.from(fullSeatMap);
      }

      await db.transaction((txn) async {
        for (final entry in changed) {
          await _seatMapStore.record(entry.key).put(txn, entry.value);
        }
        for (final key in removed) {
          await _seatMapStore.record(key).delete(txn);
        }
        await _metaStore.record(_seatMapTsKey).put(txn, _nowMs());
      });

      _seatMapSnapshot = Map<int, int>.from(fullSeatMap);
      return Map<int, int>.from(fullSeatMap);
    } catch (_) {
      final fallback = Map<int, int>.from(fullSeatMap);
      _seatMapSnapshot = fallback;
      return fallback;
    }
  }

  Future<void> saveDetailsCache(
    Map<int, SeatStatusDetailsResponse> detailsBySection,
  ) async {
    if (detailsBySection.isEmpty) return;
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        var wroteAny = false;
        for (final entry in detailsBySection.entries) {
          final nextJson = entry.value.toJson();
          final existingRaw = await _detailsStore.record(entry.key).get(txn);
          Map<String, dynamic>? existingJson;
          if (existingRaw is Map<String, dynamic>) {
            existingJson = existingRaw;
          } else if (existingRaw is Map) {
            existingJson = existingRaw.cast<String, dynamic>();
          }
          if (existingJson != null && _jsonDeepEqual(existingJson, nextJson)) {
            continue;
          }
          await _detailsStore.record(entry.key).put(txn, nextJson);
          wroteAny = true;
        }
        if (wroteAny) {
          await _metaStore.record(_detailsTsKey).put(txn, _nowMs());
        }
      });
    } catch (_) {}
  }

  Future<Map<int, int>> fetchSeatMapFromApi() async {
    const path = '/adv/v1/advising/sections/seat-status';
    final url = '${ApiConfig.connectApiBase}$path';
    final db = await _openDb();
    final etag = await _metaStore.record(_seatMapEtagKey).get(db) as String?;
    final response = await _client.authenticatedGetWithEtag(url, etag: etag);
    if (response.statusCode == 304) {
      return Map<int, int>.from(await _getSeatMapSnapshot(db));
    }
    final raw = jsonDecode(response.body);
    if (raw is! Map) return const <int, int>{};
    final map = <int, int>{};
    for (final entry in raw.entries) {
      final sectionId = int.tryParse('${entry.key}');
      final remaining = int.tryParse('${entry.value}');
      if (sectionId == null || remaining == null) continue;
      map[sectionId] = remaining;
    }
    if (map.isEmpty) return const <int, int>{};
    final saved = await replaceSeatMapSnapshotAndSave(map);
    final nextEtag = extractEtagFromResponse(response);
    if (nextEtag != null) {
      await _metaStore.record(_seatMapEtagKey).put(db, nextEtag);
    }
    return saved;
  }

  Future<Map<int, SeatStatusDetailsResponse>> fetchDetailsForSectionIdsFromApi(
    List<int> sectionIds, {
    int concurrency = 8,
  }) async {
    if (sectionIds.isEmpty) return const <int, SeatStatusDetailsResponse>{};
    final uniqueIds = sectionIds.toSet().toList()..sort((a, b) => a - b);
    final result = <int, SeatStatusDetailsResponse>{};
    final db = await _openDb();
    final nextEtags = <int, String>{};
    var index = 0;
    while (index < uniqueIds.length) {
      final end = (index + concurrency > uniqueIds.length)
          ? uniqueIds.length
          : index + concurrency;
      final batch = uniqueIds.sublist(index, end);
      await Future.wait(
        batch.map((sectionId) async {
          final url =
              '${ApiConfig.connectApiBase}/adv/v1/advising/sections/$sectionId/details';
          try {
            final etagKey = '$_detailsEtagPrefix$sectionId';
            final etag = await _metaStore.record(etagKey).get(db) as String?;
            final response = await _client.authenticatedGetWithEtag(
              url,
              etag: etag,
            );
            if (response.statusCode == 304) {
              final cached = await _loadCachedDetailsBySectionId(db, sectionId);
              if (cached != null) {
                result[sectionId] = cached;
                return;
              }
              final retry = await _client.authenticatedGet(url);
              final retryRaw = jsonDecode(retry.body);
              if (retryRaw is! Map<String, dynamic>) return;
              result[sectionId] = SeatStatusDetailsResponse.fromJson(retryRaw);
              final retryEtag = extractEtagFromResponse(retry);
              if (retryEtag != null) {
                nextEtags[sectionId] = retryEtag;
              }
              return;
            }
            final raw = jsonDecode(response.body);
            if (raw is! Map<String, dynamic>) return;
            result[sectionId] = SeatStatusDetailsResponse.fromJson(raw);
            final nextEtag = extractEtagFromResponse(response);
            if (nextEtag != null) {
              nextEtags[sectionId] = nextEtag;
            }
          } catch (_) {}
        }),
      );
      index = end;
    }
    if (result.isNotEmpty) {
      await saveDetailsCache(result);
    }
    if (nextEtags.isNotEmpty) {
      await _saveDetailsEtags(nextEtags);
    }
    return result;
  }

  Future<void> preloadSeatStatusCache({
    int detailChunkSize = 40,
    int detailConcurrency = 8,
  }) async {
    try {
      final seatMap = await fetchSeatMapFromApi();
      if (seatMap.isEmpty) return;
      final db = await _openDb();
      final existingDetails = await _detailsStore.findKeys(db);
      final cachedIds = existingDetails.toSet();
      final missing = seatMap.keys.where((id) => !cachedIds.contains(id)).toList()
        ..sort((a, b) => a.compareTo(b));
      if (missing.isEmpty) return;

      final chunk = detailChunkSize <= 0 ? 40 : detailChunkSize;
      var index = 0;
      while (index < missing.length) {
        final end = (index + chunk > missing.length)
            ? missing.length
            : index + chunk;
        final batch = missing.sublist(index, end);
        await fetchDetailsForSectionIdsFromApi(
          batch,
          concurrency: detailConcurrency,
        );
        index = end;
      }
    } catch (_) {}
  }

  Future<Database> _openDb() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/$_dbName';
    final db = await databaseFactoryIo.openDatabase(dbPath);
    await _cleanupLegacySharedPrefsCacheOnce();
    _db = db;
    return db;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _cleanupLegacySharedPrefsCacheOnce() async {
    try {
      final prefs = SharedPreferencesAsync();
      final done = await prefs.getBool(_legacyCleanupDoneKey);
      if (done == true) return;
      for (final key in _legacySharedPrefsKeys) {
        await prefs.remove(key);
      }
      await prefs.setBool(_legacyCleanupDoneKey, true);
    } catch (_) {}
  }

  Future<Map<int, int>> _getSeatMapSnapshot(Database db) async {
    final cached = _seatMapSnapshot;
    if (cached != null) return cached;
    final snapshots = await _seatMapStore.find(db);
    final existing = <int, int>{};
    for (final snap in snapshots) {
      final value = snap.value;
      if (value is int) {
        existing[snap.key] = value;
      } else {
        final parsed = int.tryParse('$value');
        if (parsed != null) {
          existing[snap.key] = parsed;
        }
      }
    }
    _seatMapSnapshot = existing;
    return existing;
  }

  Future<SeatStatusDetailsResponse?> _loadCachedDetailsBySectionId(
    Database db,
    int sectionId,
  ) async {
    try {
      final raw = await _detailsStore.record(sectionId).get(db);
      if (raw is! Map) return null;
      return SeatStatusDetailsResponse.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveDetailsEtags(Map<int, String> etags) async {
    if (etags.isEmpty) return;
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        for (final entry in etags.entries) {
          final value = entry.value.trim();
          if (value.isEmpty) continue;
          await _metaStore
              .record('$_detailsEtagPrefix${entry.key}')
              .put(txn, value);
        }
      });
    } catch (_) {}
  }
}

bool _jsonDeepEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  return jsonEncode(a) == jsonEncode(b);
}

Map<int, SeatStatusDetailsResponse> _parseCachedDetailsFromMap(
  Map<String, dynamic> decoded,
) {
  final result = <int, SeatStatusDetailsResponse>{};
  for (final entry in decoded.entries) {
    final key = int.tryParse(entry.key);
    if (key == null) continue;
    if (entry.value is! Map) continue;
    try {
      result[key] = SeatStatusDetailsResponse.fromJson(
        (entry.value as Map).cast<String, dynamic>(),
      );
    } catch (_) {}
  }
  return result;
}

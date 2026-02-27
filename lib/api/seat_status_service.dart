import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatStatusService {
  SeatStatusService._internal();

  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  Database? _db;
  Map<int, int>? _seatMapSnapshot;
  Map<String, SeatFacultyProfile>? _facultySnapshot;
  final ApiClient _client = ApiClient();

  static const String _dbName = 'seat_status_cache.db';
  static const String _detailsTsKey = 'details_ts';
  static const String _seatMapTsKey = 'seat_map_ts';
  static const String _facultyTsKey = 'faculty_ts';
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
  final StoreRef<String, Object?> _facultyStore = StoreRef<String, Object?>(
    'seat_status_faculty',
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

  Future<Map<String, SeatFacultyProfile>> loadCachedFacultyProfiles({
    Duration maxAge = const Duration(days: 30),
  }) async {
    try {
      final db = await _openDb();
      final ts = await _metaStore.record(_facultyTsKey).get(db) as int?;
      if (ts == null) return const <String, SeatFacultyProfile>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <String, SeatFacultyProfile>{};
      final snapshots = await _facultyStore.find(db);
      if (snapshots.isEmpty) return const <String, SeatFacultyProfile>{};
      final result = <String, SeatFacultyProfile>{};
      for (final snap in snapshots) {
        final raw = snap.value;
        if (raw is! Map) continue;
        final key = snap.key.trim().toUpperCase();
        if (key.isEmpty) continue;
        try {
          result[key] = SeatFacultyProfile.fromJson(
            raw.cast<String, dynamic>(),
          );
        } catch (_) {}
      }
      _facultySnapshot = Map<String, SeatFacultyProfile>.from(result);
      return result;
    } catch (_) {
      return const <String, SeatFacultyProfile>{};
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
        for (final entry in detailsBySection.entries) {
          await _detailsStore.record(entry.key).put(txn, entry.value.toJson());
        }
        await _metaStore.record(_detailsTsKey).put(txn, _nowMs());
      });
    } catch (_) {}
  }

  Future<void> saveFacultyProfiles(
    Map<String, SeatFacultyProfile> profiles,
  ) async {
    if (profiles.isEmpty) return;
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        for (final entry in profiles.entries) {
          final key = entry.key.trim().toUpperCase();
          if (key.isEmpty) continue;
          await _facultyStore.record(key).put(txn, entry.value.toJson());
        }
        await _metaStore.record(_facultyTsKey).put(txn, _nowMs());
      });
      final merged = <String, SeatFacultyProfile>{
        ...?_facultySnapshot,
        ...profiles.map((k, v) => MapEntry(k.trim().toUpperCase(), v)),
      };
      _facultySnapshot = merged;
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
    final nextEtag = _extractEtag(response);
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
              final retryEtag = _extractEtag(retry);
              if (retryEtag != null) {
                nextEtags[sectionId] = retryEtag;
              }
              return;
            }
            final raw = jsonDecode(response.body);
            if (raw is! Map<String, dynamic>) return;
            result[sectionId] = SeatStatusDetailsResponse.fromJson(raw);
            final nextEtag = _extractEtag(response);
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

  Future<Map<String, SeatFacultyProfile>> fetchMissingFacultyProfiles(
    Set<String> initials, {
    int concurrency = 6,
  }) async {
    if (initials.isEmpty) return const <String, SeatFacultyProfile>{};
    final existing = _facultySnapshot ?? await loadCachedFacultyProfiles();

    final targets = initials
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .where(_isMeaningfulFacultyToken)
        .where((e) => !existing.containsKey(e))
        .toList()
      ..sort();
    if (targets.isEmpty) return const <String, SeatFacultyProfile>{};

    final fetched = <String, SeatFacultyProfile>{};
    final laneCount = concurrency <= 0 ? 1 : concurrency;
    var index = 0;
    while (index < targets.length) {
      final end = (index + laneCount > targets.length)
          ? targets.length
          : index + laneCount;
      final batch = targets.sublist(index, end);
      final batchResults = await Future.wait<MapEntry<String, SeatFacultyProfile>?>(
        batch.map((initial) async {
          final staffId = await _resolveStaffIdByInitial(initial);
          if (staffId == null || staffId.isEmpty) return null;
          final profile = await _fetchFacultyProfileByStaffId(staffId, initial);
          if (profile == null) return null;
          return MapEntry(initial, profile);
        }),
      );
      for (final entry in batchResults) {
        if (entry == null) continue;
        fetched[entry.key] = entry.value;
      }
      index = end;
    }
    if (fetched.isNotEmpty) {
      await saveFacultyProfiles(fetched);
    }
    return fetched;
  }

  Future<String?> _resolveStaffIdByInitial(String initial) async {
    try {
      final normalized = initial.trim().toUpperCase();
      if (normalized.isEmpty) return null;
      for (var page = 1; page <= 3; page++) {
        final query = Uri.encodeQueryComponent(normalized.toLowerCase());
        final url =
            '${ApiConfig.connectApiBase}/data/autocomplete'
            '?q=$query&page=$page&field_name=staffId&type=staff';
        final response = await _client.authenticatedGet(url);
        final raw = jsonDecode(response.body);
        if (raw is! Map<String, dynamic>) continue;
        final results = raw['results'];
        if (results is! List) continue;
        final more = raw['more'] == true;

        for (final item in results.whereType<Map>()) {
          final map = item.cast<String, dynamic>();
          final id = '${map['id'] ?? ''}'.trim();
          final text = '${map['text'] ?? ''}'.trim();
          if (id.isEmpty || text.isEmpty) continue;

          final token = _extractFacultyInitialToken(text);
          if (token == normalized) {
            return id;
          }
        }
        if (!more) break;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<SeatFacultyProfile?> _fetchFacultyProfileByStaffId(
    String staffId,
    String initial,
  ) async {
    final url =
        '${ApiConfig.connectApiBase}/reg/v1/consultation-hours/$staffId';
    try {
      final response = await _client.authenticatedGet(url);
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) return null;
      return SeatFacultyProfile(
        staffId: '${raw['id'] ?? staffId}'.trim(),
        shortName: initial,
        name: '${raw['staffName'] ?? ''}'.trim(),
        email: '${raw['email'] ?? ''}'.trim(),
        phone: '${raw['phone'] ?? ''}'.trim(),
        designation: '${raw['designation'] ?? ''}'.trim(),
      );
    } catch (_) {
      return null;
    }
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

String? _extractEtag(http.Response response) {
  try {
    final headers = response.headers;
    for (final entry in headers.entries) {
      final key = entry.key.trim().toLowerCase();
      if (key != 'etag') continue;
      final value = entry.value.trim();
      if (value.isEmpty) return null;
      return value;
    }
  } catch (_) {}
  return null;
}

String _extractFacultyInitialToken(String text) {
  final match = RegExp(r'^\s*([A-Za-z0-9]+)').firstMatch(text);
  if (match == null) return '';
  return (match.group(1) ?? '').trim().toUpperCase();
}

bool _isMeaningfulFacultyToken(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return false;
  if (v == 'TBA') return false;
  if (v == 'TO BE ANNOUNCED') return false;
  if (v == 'N/A') return false;
  if (v == 'NULL') return false;
  if (v == '--') return false;
  return true;
}

class SeatFacultyProfile {
  const SeatFacultyProfile({
    required this.staffId,
    required this.shortName,
    required this.name,
    required this.email,
    required this.phone,
    required this.designation,
  });

  final String staffId;
  final String shortName;
  final String name;
  final String email;
  final String phone;
  final String designation;

  factory SeatFacultyProfile.fromJson(Map<String, dynamic> json) {
    return SeatFacultyProfile(
      staffId: '${json['staffId'] ?? ''}'.trim(),
      shortName: '${json['shortName'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      phone: '${json['phone'] ?? ''}'.trim(),
      designation: '${json['designation'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'staffId': staffId,
    'shortName': shortName,
    'name': name,
    'email': email,
    'phone': phone,
    'designation': designation,
  };
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

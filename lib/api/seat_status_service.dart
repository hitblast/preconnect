import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatStatusService {
  SeatStatusService._internal();

  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  Database? _db;
  Map<int, int>? _seatMapSnapshot;
  Map<int, SeatStatusDetailsResponse>? _detailsSnapshot;
  int? _detailsSnapshotTs;
  Map<String, SeatStatusStaffInfo>? _staffSnapshot;
  final ApiClient _client = ApiClient();
  final Map<String, SeatStatusStaffInfo> _staffInfoByInitialCache =
      <String, SeatStatusStaffInfo>{};
  final Map<String, Future<SeatStatusStaffInfo?>> _staffInfoInFlight =
      <String, Future<SeatStatusStaffInfo?>>{};

  String get _proxyBase {
    final base = ApiConfig.seatStatusProxyBase.trim();
    if (base.isEmpty) {
      throw StateError('Missing Seat Status proxy base URL');
    }
    return base;
  }

  String get seatStatusStreamUrl {
    return '$_proxyBase/seat-status/stream';
  }

  String _sectionDetailsUrl(int sectionId) {
    return '$_proxyBase/sections/$sectionId/details';
  }

  String get _allSectionsDetailsUrl {
    return '$_proxyBase/sections/details';
  }

  String _staffByInitialUrl(String initial) {
    return '$_proxyBase/staff/${Uri.encodeComponent(initial)}';
  }

  static const String _dbName = 'seat_status_cache.db';
  static const String _detailsTsKey = 'details_ts';
  static const String _seatMapTsKey = 'seat_map_ts';
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
  final StoreRef<String, Object?> _staffStore = StoreRef<String, Object?>(
    'seat_status_staff',
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
      final snapshot = await _getSeatMapSnapshot(db);
      if (snapshot.isEmpty) return const <int, int>{};
      return Map<int, int>.from(snapshot);
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
      if (_detailsSnapshotTs == ts && _detailsSnapshot != null) {
        return Map<int, SeatStatusDetailsResponse>.from(_detailsSnapshot!);
      }
      final snapshot = await _getDetailsSnapshot(db);
      _detailsSnapshotTs = ts;
      _detailsSnapshot = Map<int, SeatStatusDetailsResponse>.from(snapshot);
      if (snapshot.isEmpty) return const <int, SeatStatusDetailsResponse>{};
      return Map<int, SeatStatusDetailsResponse>.from(snapshot);
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
      _detailsSnapshot = null;
      _detailsSnapshotTs = null;
    } catch (_) {}
  }

  Future<Map<int, SeatStatusDetailsResponse>> fetchDetailsForSectionIdsFromApi(
    List<int> sectionIds, {
    int concurrency = 8,
  }) async {
    if (sectionIds.isEmpty) return const <int, SeatStatusDetailsResponse>{};
    final uniqueIds = sectionIds.toSet().toList()..sort((a, b) => a - b);
    try {
      final allDetails = await fetchAllSectionsDetailsFromApi();
      if (allDetails.isNotEmpty) {
        final filtered = <int, SeatStatusDetailsResponse>{};
        for (final id in uniqueIds) {
          final details = allDetails[id];
          if (details != null) filtered[id] = details;
        }
        return filtered;
      }
    } catch (_) {}

    // Fallback: direct per-section fetch if bundle route is unavailable.
    final result = <int, SeatStatusDetailsResponse>{};
    var index = 0;
    while (index < uniqueIds.length) {
      final end = (index + concurrency > uniqueIds.length)
          ? uniqueIds.length
          : index + concurrency;
      final batch = uniqueIds.sublist(index, end);
      await Future.wait(
        batch.map((sectionId) async {
          final url = _sectionDetailsUrl(sectionId);
          try {
            final response = await _client.publicGet(
              url,
              acceptedStatusCodes: const <int>{200},
            );
            final raw = jsonDecode(response.body);
            if (raw is! Map<String, dynamic>) return;
            result[sectionId] = SeatStatusDetailsResponse.fromJson(raw);
          } catch (_) {}
        }),
      );
      index = end;
    }
    if (result.isNotEmpty) {
      await saveDetailsCache(result);
    }
    return result;
  }

  Future<Map<int, SeatStatusDetailsResponse>> fetchAllSectionsDetailsFromApi()
  async {
    final response = await _client.publicGet(
      _allSectionsDetailsUrl,
      acceptedStatusCodes: const <int>{200},
    );
    final raw = jsonDecode(response.body);
    if (raw is! Map) return const <int, SeatStatusDetailsResponse>{};
    final allDetails = _parseCachedDetailsFromMap(
      raw.map((key, value) => MapEntry('$key', value)),
    );
    if (allDetails.isNotEmpty) {
      await saveDetailsCache(allDetails);
    }
    return allDetails;
  }

  Future<Map<String, SeatStatusStaffInfo>> loadCachedStaffInfoByInitials(
    Iterable<String> initials,
  ) async {
    final keys =
        initials
            .map((e) => e.trim().toUpperCase())
            .where(_isMeaningfulInitial)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (keys.isEmpty) return const <String, SeatStatusStaffInfo>{};
    try {
      final db = await _openDb();
      final output = <String, SeatStatusStaffInfo>{};
      final unresolved = <String>[];
      for (final key in keys) {
        final cached = _staffInfoByInitialCache[key];
        if (cached != null) {
          output[key] = cached;
        } else {
          unresolved.add(key);
        }
      }
      if (unresolved.isNotEmpty) {
        final snapshot = await _getStaffSnapshot(db);
        for (final key in unresolved) {
          final info = snapshot[key];
          if (info == null) continue;
          _staffInfoByInitialCache[key] = info;
          output[key] = info;
        }
      }
      return output;
    } catch (_) {
      return const <String, SeatStatusStaffInfo>{};
    }
  }

  Future<void> preloadSeatStatusCache({
    int detailChunkSize = 40,
    int detailConcurrency = 8,
  }) async {
    try {
      final db = await _openDb();
      final allDetails = await fetchAllSectionsDetailsFromApi();
      if (allDetails.isEmpty) return;
      final sectionIds = allDetails.keys.toSet();
      final existingDetails = await _detailsStore.findKeys(db);
      final cachedIds = existingDetails.toSet();
      final stale = cachedIds.where((id) => !sectionIds.contains(id)).toList()
        ..sort((a, b) => a.compareTo(b));

      if (stale.isNotEmpty) {
        await db.transaction((txn) async {
          for (final sectionId in stale) {
            await _detailsStore.record(sectionId).delete(txn);
            await _metaStore
                .record('$_detailsEtagPrefix$sectionId')
                .delete(txn);
          }
        });
        _detailsSnapshot = null;
        _detailsSnapshotTs = null;
      }

      final detailsSnapshot = allDetails;
      final initials = <String>{};
      for (final sectionId in detailsSnapshot.keys) {
        final details = detailsSnapshot[sectionId];
        if (details == null) continue;
        final main = details.section.faculties.trim().toUpperCase();
        if (_isMeaningfulInitial(main)) initials.add(main);
        final child = (details.childSection?.faculties ?? '')
            .trim()
            .toUpperCase();
        if (_isMeaningfulInitial(child)) initials.add(child);
      }
      if (initials.isNotEmpty) {
        await resolveStaffInfoByInitials(
          initials,
          concurrency: detailConcurrency <= 0 ? 6 : detailConcurrency,
        );
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

  Future<Map<String, SeatStatusStaffInfo>> resolveStaffInfoByInitials(
    Iterable<String> initials, {
    int concurrency = 6,
  }) async {
    final requested =
        initials
            .map((e) => e.trim().toUpperCase())
            .where(_isMeaningfulInitial)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (requested.isEmpty) return const <String, SeatStatusStaffInfo>{};

    final chunkSize = concurrency <= 0 ? 6 : concurrency;
    var index = 0;
    while (index < requested.length) {
      final end = (index + chunkSize > requested.length)
          ? requested.length
          : index + chunkSize;
      final batch = requested.sublist(index, end);
      await Future.wait(batch.map((key) => _resolveStaffInfoForInitial(key)));
      index = end;
    }

    final output = <String, SeatStatusStaffInfo>{};
    for (final key in requested) {
      final value = _staffInfoByInitialCache[key];
      if (value == null) continue;
      output[key] = value;
    }
    return output;
  }

  Future<SeatStatusStaffInfo?> _resolveStaffInfoForInitial(
    String initial,
  ) async {
    final key = initial.trim().toUpperCase();
    if (!_isMeaningfulInitial(key)) return null;
    final cached = _staffInfoByInitialCache[key];
    if (cached != null) return cached;

    final fromDb = await _loadStaffInfoFromDb(key);
    if (fromDb != null) {
      _staffInfoByInitialCache[key] = fromDb;
      return fromDb;
    }

    final existing = _staffInfoInFlight[key];
    if (existing != null) return existing;

    final future = _fetchStaffInfoByInitialFromProxy(key);
    _staffInfoInFlight[key] = future;
    try {
      final info = await future;
      if (info != null) {
        _staffInfoByInitialCache[key] = info;
        await _saveStaffInfoToDb(info);
      }
      return info;
    } finally {
      _staffInfoInFlight.remove(key);
    }
  }

  Future<SeatStatusStaffInfo?> _fetchStaffInfoByInitialFromProxy(
    String initial,
  ) async {
    final url = _staffByInitialUrl(initial);
    try {
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200, 404},
      );
      if (response.statusCode != 200) return null;
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) return null;
      return SeatStatusStaffInfo.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isMeaningfulInitial(String value) {
    if (value.trim().isEmpty) return false;
    const bad = <String>{'TBA', 'NULL', 'N/A', '--'};
    return !bad.contains(value.trim().toUpperCase());
  }

  Future<SeatStatusStaffInfo?> _loadStaffInfoFromDb(String initial) async {
    try {
      final db = await _openDb();
      final snapshot = await _getStaffSnapshot(db);
      return snapshot[initial];
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveStaffInfoToDb(SeatStatusStaffInfo info) async {
    try {
      final db = await _openDb();
      final key = info.shortName.toUpperCase();
      await _staffStore.record(key).put(db, info.toJson());
      _staffSnapshot ??= <String, SeatStatusStaffInfo>{};
      _staffSnapshot![key] = info;
    } catch (_) {}
  }

  Future<Map<int, SeatStatusDetailsResponse>> _getDetailsSnapshot(
    Database db,
  ) async {
    final cached = _detailsSnapshot;
    if (cached != null) return cached;
    final snapshots = await _detailsStore.find(db);
    if (snapshots.isEmpty) {
      _detailsSnapshot = <int, SeatStatusDetailsResponse>{};
      return _detailsSnapshot!;
    }
    final raw = <String, dynamic>{};
    for (final snap in snapshots) {
      if (snap.value is Map<String, dynamic>) {
        raw[snap.key.toString()] = snap.value;
      } else if (snap.value is Map) {
        raw[snap.key.toString()] = (snap.value as Map).cast<String, dynamic>();
      }
    }
    _detailsSnapshot = _parseCachedDetailsFromMap(raw);
    return _detailsSnapshot!;
  }

  Future<Map<String, SeatStatusStaffInfo>> _getStaffSnapshot(
    Database db,
  ) async {
    final cached = _staffSnapshot;
    if (cached != null) return cached;
    final records = await _staffStore.find(db);
    final map = <String, SeatStatusStaffInfo>{};
    for (final record in records) {
      final raw = record.value;
      if (raw is! Map) continue;
      final key = record.key.trim().toUpperCase();
      if (!_isMeaningfulInitial(key)) continue;
      try {
        map[key] = SeatStatusStaffInfo.fromJson(raw.cast<String, dynamic>());
      } catch (_) {}
    }
    _staffSnapshot = map;
    return map;
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

class SeatStatusStaffInfo {
  const SeatStatusStaffInfo({
    required this.staffId,
    required this.shortName,
    required this.staffName,
    required this.email,
    required this.departmentId,
    required this.designationId,
  });

  final int staffId;
  final String shortName;
  final String staffName;
  final String email;
  final int? departmentId;
  final int? designationId;

  factory SeatStatusStaffInfo.fromJson(Map<String, dynamic> json) {
    return SeatStatusStaffInfo(
      staffId: int.tryParse('${json['staffId'] ?? 0}') ?? 0,
      shortName: '${json['shortName'] ?? ''}'.trim(),
      staffName: '${json['staffName'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      departmentId: int.tryParse('${json['departmentId'] ?? ''}'),
      designationId: int.tryParse('${json['designationId'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'staffId': staffId,
      'shortName': shortName,
      'staffName': staffName,
      'email': email,
      'departmentId': departmentId,
      'designationId': designationId,
    };
  }
}

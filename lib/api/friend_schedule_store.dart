import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:sembast/sembast_io.dart';

class FriendScheduleStore {
  FriendScheduleStore._internal();

  static final FriendScheduleStore _instance = FriendScheduleStore._internal();
  factory FriendScheduleStore() => _instance;

  static const String _dbName = 'friend_schedule.db';

  final StoreRef<String, Object?> _scheduleStore = StoreRef<String, Object?>(
    'friend_schedules',
  );
  final StoreRef<String, Object?> _metadataStore = StoreRef<String, Object?>(
    'friend_metadata',
  );

  Database? _db;

  Future<FriendScheduleStoreSnapshot> loadSnapshot() async {
    try {
      final db = await _openDb();
      final scheduleSnaps = await _scheduleStore.find(db);
      final metadataSnaps = await _metadataStore.find(db);

      final encodedSchedules = <String>[];
      for (final snap in scheduleSnaps) {
        final value = snap.value;
        if (value is! Map) continue;
        final encoded = '${value['encoded'] ?? ''}'.trim();
        if (encoded.isNotEmpty) {
          encodedSchedules.add(encoded);
        }
      }

      final metadata = <String, FriendMetadata>{};
      for (final snap in metadataSnaps) {
        final value = snap.value;
        if (value is! Map) continue;
        try {
          metadata[snap.key] = FriendMetadata.fromJson(
            value.cast<String, dynamic>(),
          );
        } catch (_) {}
      }

      return FriendScheduleStoreSnapshot(
        encodedSchedules: encodedSchedules,
        metadata: metadata,
      );
    } catch (_) {
      return const FriendScheduleStoreSnapshot(
        encodedSchedules: <String>[],
        metadata: <String, FriendMetadata>{},
      );
    }
  }

  Future<void> upsertEncodedSchedule(String encodedValue) async {
    final encoded = encodedValue.trim();
    if (encoded.isEmpty) return;
    final friendId = _extractFriendId(encoded);
    if (friendId == null || friendId.isEmpty) return;

    try {
      final db = await _openDb();
      await _scheduleStore.record(friendId).put(db, <String, Object?>{
        'encoded': encoded,
      });
    } catch (_) {}
  }

  Future<void> removeByEncoded(String encodedValue) async {
    final encoded = encodedValue.trim();
    if (encoded.isEmpty) return;
    final friendId = _extractFriendId(encoded);

    try {
      final db = await _openDb();
      if (friendId != null && friendId.isNotEmpty) {
        await _scheduleStore.record(friendId).delete(db);
        return;
      }
      final snaps = await _scheduleStore.find(db);
      for (final snap in snaps) {
        final value = snap.value;
        if (value is! Map) continue;
        if ('${value['encoded'] ?? ''}'.trim() == encoded) {
          await _scheduleStore.record(snap.key).delete(db);
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> saveAllMetadata(Map<String, FriendMetadata> metadata) async {
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        await _metadataStore.delete(txn);
        for (final entry in metadata.entries) {
          await _metadataStore.record(entry.key).put(txn, entry.value.toJson());
        }
      });
    } catch (_) {}
  }

  Future<void> clearAll() async {
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        await _scheduleStore.delete(txn);
        await _metadataStore.delete(txn);
      });
    } catch (_) {}
  }

  Future<Database> _openDb() async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/$_dbName';
    final db = await databaseFactoryIo.openDatabase(dbPath);
    _db = db;
    return db;
  }

  String? _extractFriendId(String base64Data) {
    try {
      final decodedBase64 = base64.decode(base64Data);
      final decodedGzip = GZipDecoder().decodeBytes(decodedBase64);
      final originalJson = utf8.decode(decodedGzip);
      final parsed = jsonDecode(originalJson);
      if (parsed is Map<String, dynamic>) {
        final id = parsed['id']?.toString().trim() ?? '';
        return id.isEmpty ? null : id;
      }
    } catch (_) {}
    return null;
  }
}

class FriendScheduleStoreSnapshot {
  const FriendScheduleStoreSnapshot({
    required this.encodedSchedules,
    required this.metadata,
  });

  final List<String> encodedSchedules;
  final Map<String, FriendMetadata> metadata;
}

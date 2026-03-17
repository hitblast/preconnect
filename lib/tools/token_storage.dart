import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/web_kv_store_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_kv_store_web.dart';

class TokenStorage {
  TokenStorage._();

  static final TokenStorage instance = TokenStorage._();
  static const String _cachedHasSessionKey = 'cached_has_auth_session';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool get _useSecure =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.macOS;

  Future<String?> read({required String key}) async {
    if (kIsWeb) {
      final value = webKvGet(key);
      if (value != null && value.isNotEmpty) return value;
    }
    if (_useSecure) {
      return _secure.read(key: key);
    }
    final prefs = SharedPreferencesAsync();
    return prefs.getString(key);
  }

  Future<bool?> readCachedHasSession() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getBool(_cachedHasSessionKey);
  }

  Future<void> write({required String key, String? value}) async {
    if (kIsWeb && webKvSet(key, value)) {
      await _updateCachedSessionFlagForKey(key, value);
      return;
    }
    if (_useSecure) {
      await _secure.write(key: key, value: value);
      await _updateCachedSessionFlagForKey(key, value);
      return;
    }
    final prefs = SharedPreferencesAsync();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    await _updateCachedSessionFlagForKey(key, value);
  }

  Future<void> deleteAll() async {
    if (kIsWeb) {
      webKvClearKeys(const ['access_token', 'refresh_token']);
      final prefs = SharedPreferencesAsync();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.setBool(_cachedHasSessionKey, false);
      return;
    }
    if (_useSecure) {
      await _secure.deleteAll();
      final prefs = SharedPreferencesAsync();
      await prefs.setBool(_cachedHasSessionKey, false);
      return;
    }
    final prefs = SharedPreferencesAsync();
    await prefs.clear();
  }

  Future<void> _updateCachedSessionFlagForKey(String key, String? value) async {
    if (key != 'access_token') return;
    final prefs = SharedPreferencesAsync();
    final hasValue = value != null && value.isNotEmpty;
    await prefs.setBool(_cachedHasSessionKey, hasValue);
  }
}

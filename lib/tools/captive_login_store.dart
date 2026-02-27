import 'package:preconnect/tools/token_storage.dart';

class CaptiveLoginCredentials {
  const CaptiveLoginCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;
}

class CaptiveLoginStore {
  CaptiveLoginStore._();

  static final CaptiveLoginStore instance = CaptiveLoginStore._();
  static const String _usernameKey = 'wifi_captive_username';
  static const String _passwordKey = 'wifi_captive_password';
  static const String _autoExtendEnabledKey = 'wifi_captive_auto_extend';
  static const String defaultCampusSsid = 'Student-WiFi';

  final TokenStorage _storage = TokenStorage.instance;

  Future<bool> readAutoExtendEnabled() async {
    final raw = (await _storage.read(key: _autoExtendEnabledKey) ?? 'true')
        .trim()
        .toLowerCase();
    return raw != 'false';
  }

  Future<CaptiveLoginCredentials?> read() async {
    final username = (await _storage.read(key: _usernameKey) ?? '').trim();
    final password = await _storage.read(key: _passwordKey) ?? '';
    if (username.isEmpty || password.isEmpty) return null;
    return CaptiveLoginCredentials(username: username, password: password);
  }

  Future<void> save({
    required String username,
    required String password,
  }) async {
    final trimmed = username.trim();
    await _storage.write(key: _usernameKey, value: trimmed);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> saveAutoExtendEnabled(bool enabled) async {
    await _storage.write(
      key: _autoExtendEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  Future<void> clear() async {
    await _storage.write(key: _usernameKey, value: null);
    await _storage.write(key: _passwordKey, value: null);
    await _storage.write(key: _autoExtendEnabledKey, value: null);
  }
}

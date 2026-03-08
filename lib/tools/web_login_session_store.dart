import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/token_storage.dart';

class WebLoginSessionStore {
  WebLoginSessionStore._();

  static const String _expiresAtKey = 'web_login_session_expires_at';
  static const String _accountEmailKey = 'web_login_account_email';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int sessionExpiresAtMillis,
    required String accountEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await TokenStorage.instance.write(key: 'access_token', value: accessToken);
    await TokenStorage.instance.write(key: 'refresh_token', value: refreshToken);
    await prefs.setInt(_expiresAtKey, sessionExpiresAtMillis);
    await prefs.setString(_accountEmailKey, accountEmail.trim());
  }

  static Future<int?> getExpiryMillis() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_expiresAtKey);
  }

  static Future<bool> hasValidSession() async {
    final expiry = await getExpiryMillis();
    return expiry != null && expiry > DateTime.now().millisecondsSinceEpoch;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_accountEmailKey);
  }
}

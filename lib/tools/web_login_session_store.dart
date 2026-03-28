import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/token_storage.dart';

class WebLoginSessionStore {
  WebLoginSessionStore._();

  static const String _studentEmailKey = 'web_login_student_email';
  static const String _webSessionIdKey = 'web_login_session_id';
  static const String _webSessionTokenKey = 'web_login_session_token';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String studentEmail,
    String? webSessionId,
    String? webSessionToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await TokenStorage.instance.write(key: 'access_token', value: accessToken);
    await TokenStorage.instance.write(
      key: 'refresh_token',
      value: refreshToken,
    );
    await prefs.setString(_studentEmailKey, studentEmail.trim());
    final normalizedSessionId = (webSessionId ?? '').trim();
    final normalizedSessionToken = (webSessionToken ?? '').trim();
    if (normalizedSessionId.isNotEmpty && normalizedSessionToken.isNotEmpty) {
      await prefs.setString(_webSessionIdKey, normalizedSessionId);
      await prefs.setString(_webSessionTokenKey, normalizedSessionToken);
    }
  }

  static Future<bool> hasValidSession() async {
    final sessionId = await getWebSessionId();
    final sessionToken = await getWebSessionToken();
    return (sessionId ?? '').isNotEmpty && (sessionToken ?? '').isNotEmpty;
  }

  static Future<String?> getWebSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_webSessionIdKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<String?> getWebSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_webSessionTokenKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_studentEmailKey);
    await prefs.remove(_webSessionIdKey);
    await prefs.remove(_webSessionTokenKey);
  }
}

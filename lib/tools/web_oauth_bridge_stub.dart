import 'web_oauth_bridge.dart';

class _UnsupportedOAuthBridge implements WebOAuthBridge {
  @override
  Future<String> signInAndGetEmail() {
    throw Exception('Web OAuth is only available on web.');
  }
}

WebOAuthBridge createOAuthBridgeImpl() => _UnsupportedOAuthBridge();

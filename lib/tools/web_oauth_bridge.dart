import 'web_oauth_bridge_stub.dart'
    if (dart.library.html) 'web_oauth_bridge_web.dart';

abstract class WebOAuthBridge {
  Future<String> signInAndGetEmail();
}

WebOAuthBridge createOAuthBridge() => createOAuthBridgeImpl();

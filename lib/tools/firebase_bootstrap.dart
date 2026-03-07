import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:preconnect/firebase_options.dart';

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _initialized = false;
  static bool _available = false;

  static bool get isAvailable => _available;

  static Future<void> initializeIfNeeded() async {
    if (_initialized) return;
    _initialized = true;
    if (!kIsWeb) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _available = true;
    } catch (_) {
      _available = false;
    }
  }
}

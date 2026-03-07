import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();
  static const String _projectId = 'preconnect-bracu';
  static const String _storageBucket = 'preconnect-bracu.firebasestorage.app';
  static const String _messagingSenderId = '53508941136';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_WEB_APP_ID'),
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    authDomain: 'preconnect-bracu.firebaseapp.com',
    storageBucket: _storageBucket,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    iosBundleId: 'com.sabbirba.preconnect',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_MACOS_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_MACOS_APP_ID'),
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    iosBundleId: 'com.sabbirba.preconnect',
  );
}

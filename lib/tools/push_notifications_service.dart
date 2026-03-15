import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:preconnect/api/seat_alert_push_service.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  try {
    await SeatAlertPushService().handleIncomingSeatAlertPayload(message.data);
  } catch (_) {}
}

class PushNotificationsService {
  PushNotificationsService._internal();

  static final PushNotificationsService _instance =
      PushNotificationsService._internal();
  factory PushNotificationsService() => _instance;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _syncCurrentToken();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
      unawaited(_syncToken(token));
    });
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      unawaited(
        SeatAlertPushService().handleIncomingSeatAlertPayload(message.data),
      );
    });
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      await SeatAlertPushService().handleIncomingSeatAlertPayload(
        initialMessage.data,
      );
    }
    _initialized = true;
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _messageOpenedSubscription = null;
    _initialized = false;
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Future<void> _syncCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    await _syncToken(token);
  }

  Future<void> _syncToken(String? token) async {
    final normalized = (token ?? '').trim();
    if (normalized.isEmpty) return;
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    final packageInfo = await PackageInfo.fromPlatform();
    await SeatAlertPushService().configureDeviceToken(normalized);
    try {
      await SeatAlertPushService().registerDevice(
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        locale: locale,
        appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      );
      final configs = await SeatStatusService().loadSeatAlertConfigs();
      await SeatAlertPushService().syncAllSeatAlertConfigs(configs);
    } catch (_) {}
  }
}

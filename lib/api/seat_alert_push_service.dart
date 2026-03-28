import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatAlertPushService {
  SeatAlertPushService._internal();

  static final SeatAlertPushService _instance =
      SeatAlertPushService._internal();
  factory SeatAlertPushService() => _instance;

  static const String _pushEnabledKey = 'seat_alert_push_enabled_v1';
  static const String _deviceTokenKey = 'seat_alert_push_device_token_v1';
  static const String _pendingSectionIdKey =
      'seat_alert_push_pending_section_id_v1';
  static const String _pendingSourceKey = 'seat_alert_push_pending_source_v1';

  final ApiClient _client = ApiClient();

  bool _initialized = false;
  String? _deviceToken;

  bool get isEnabled => _deviceToken != null && _deviceToken!.trim().isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_pushEnabledKey) ?? false;
    final token = (prefs.getString(_deviceTokenKey) ?? '').trim();
    if (enabled && token.isNotEmpty) {
      _deviceToken = token;
    }
    _initialized = true;
  }

  Future<void> configureDeviceToken(String token) async {
    final normalized = token.trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      _deviceToken = null;
      await prefs.remove(_deviceTokenKey);
      await prefs.setBool(_pushEnabledKey, false);
      return;
    }
    _deviceToken = normalized;
    await prefs.setString(_deviceTokenKey, normalized);
    await prefs.setBool(_pushEnabledKey, true);
  }

  Future<void> registerDevice({
    required String platform,
    String? locale,
    String? appVersion,
  }) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    final payload = <String, dynamic>{
      'token': token,
      'platform': platform,
      if (locale != null && locale.trim().isNotEmpty) 'locale': locale.trim(),
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'appVersion': appVersion.trim(),
    };
    await _client.authenticatedRequest(
      'POST',
      '${ApiConfig.pushAlertsBase}${ApiConfig.pushDeviceRegisterPath}',
      body: jsonEncode(payload),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }

  Future<void> unregisterDevice() async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    await _client.authenticatedRequest(
      'POST',
      '${ApiConfig.pushAlertsBase}${ApiConfig.pushDeviceUnregisterPath}',
      body: jsonEncode(<String, dynamic>{'token': token}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 204},
    );
  }

  Future<void> syncSeatAlertConfig(SeatAlertConfig config) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty || !config.hasAnyRule) return;
    final payload = <String, dynamic>{
      'token': token,
      'sectionId': config.sectionId,
      'rules': _rulesPayload(config),
    };
    await _client.authenticatedRequest(
      'PUT',
      '${ApiConfig.pushAlertsBase}${ApiConfig.seatAlertSubscriptionPath(config.sectionId)}',
      body: jsonEncode(payload),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }

  Future<void> removeSeatAlertConfig(int sectionId) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    await _client.authenticatedRequest(
      'DELETE',
      '${ApiConfig.pushAlertsBase}${ApiConfig.seatAlertSubscriptionPath(sectionId)}',
      body: jsonEncode(<String, dynamic>{'token': token}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 204},
    );
  }

  Future<void> syncAllSeatAlertConfigs(
    Map<int, SeatAlertConfig> configs,
  ) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    final subscriptions = configs.values
        .where((config) => config.hasAnyRule)
        .map(
          (config) => <String, dynamic>{
            'sectionId': config.sectionId,
            'rules': _rulesPayload(config),
          },
        )
        .toList();
    await _client.authenticatedRequest(
      'PUT',
      '${ApiConfig.pushAlertsBase}${ApiConfig.seatAlertSubscriptionsPath}',
      body: jsonEncode(<String, dynamic>{
        'token': token,
        'subscriptions': subscriptions,
      }),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }

  Future<void> clearAll() async {
    await unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    _deviceToken = null;
    await prefs.remove(_deviceTokenKey);
    await prefs.setBool(_pushEnabledKey, false);
  }

  Future<void> handleIncomingSeatAlertPayload(
    Map<String, dynamic> payload,
  ) async {
    final kind = '${payload['kind'] ?? payload['type'] ?? ''}'.trim();
    if (kind != 'seat_alert') return;
    final sectionId = int.tryParse('${payload['sectionId'] ?? ''}');
    if (sectionId == null || sectionId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingSectionIdKey, sectionId);
    await prefs.setString(
      _pendingSourceKey,
      '${payload['source'] ?? 'push'}'.trim(),
    );
    HomePage.requestShortcutTab(HomeTab.seatStatus);
  }

  Future<int?> consumePendingSectionId() async {
    final prefs = await SharedPreferences.getInstance();
    final sectionId = prefs.getInt(_pendingSectionIdKey);
    if (sectionId != null) {
      await prefs.remove(_pendingSectionIdKey);
      await prefs.remove(_pendingSourceKey);
    }
    return sectionId;
  }

  Map<String, dynamic> _rulesPayload(SeatAlertConfig config) {
    return <String, dynamic>{
      if (config.notifyOnAvailable)
        'available': <String, dynamic>{'oneTime': config.availableOneTime},
      if (config.thresholdSeats != null)
        'threshold': <String, dynamic>{
          'minSeats': config.thresholdSeats,
          'oneTime': config.thresholdOneTime,
        },
      if (config.notifyOnAnyChange)
        'changed': <String, dynamic>{
          'cooldownMinutes': config.changeCooldownMinutes,
        },
    };
  }
}

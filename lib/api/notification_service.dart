import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/sembast_cache.dart';

class RecentConnectNotification {
  const RecentConnectNotification({
    required this.id,
    required this.title,
    required this.module,
    required this.link,
    required this.createdOn,
    required this.expireAt,
    required this.seen,
  });

  final int id;
  final String title;
  final String module;
  final String? link;
  final DateTime? createdOn;
  final DateTime? expireAt;
  final bool seen;

  factory RecentConnectNotification.fromJson(Map<String, dynamic> json) {
    return RecentConnectNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      module: (json['module'] as String? ?? '').trim(),
      link: (json['link'] as String?)?.trim(),
      createdOn: DateTime.tryParse((json['createdOn'] as String? ?? '').trim()),
      expireAt: DateTime.tryParse((json['expireAt'] as String? ?? '').trim()),
      seen: json['seen'] == true,
    );
  }
}

class NotificationsFeed {
  const NotificationsFeed({required this.newCount, required this.items});

  final int newCount;
  final List<RecentConnectNotification> items;

  factory NotificationsFeed.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => RecentConnectNotification.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <RecentConnectNotification>[];
    return NotificationsFeed(
      newCount: (json['new'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }

  NotificationsFeed copyWith({
    int? newCount,
    List<RecentConnectNotification>? items,
  }) {
    return NotificationsFeed(
      newCount: newCount ?? this.newCount,
      items: items ?? this.items,
    );
  }
}

class ConnectNotificationDetail {
  const ConnectNotificationDetail({
    required this.id,
    required this.title,
    required this.module,
    required this.link,
    required this.expireAt,
    required this.createdOn,
    required this.details,
  });

  final int id;
  final String title;
  final String module;
  final String? link;
  final DateTime? expireAt;
  final DateTime? createdOn;
  final String details;

  factory ConnectNotificationDetail.fromJson(Map<String, dynamic> json) {
    return ConnectNotificationDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      module: (json['module'] as String? ?? '').trim(),
      link: (json['link'] as String?)?.trim(),
      expireAt: DateTime.tryParse((json['expireAt'] as String? ?? '').trim()),
      createdOn: DateTime.tryParse((json['createdOn'] as String? ?? '').trim()),
      details: (json['details'] as String? ?? '').trim(),
    );
  }
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'RecentNotificationsFeed';

  Future<NotificationsFeed?> fetchRecentNotifications({bool fromGet = false}) {
    return _client.fetchWithFallback<NotificationsFeed>(
      url: '${ApiConfig.connectApiBase}${ApiConfig.recentNotificationsPath}',
      fromGet: fromGet,
      cacheResponse: (response) async {
        await SembastCache().setString(_cacheKey, response.body);
      },
      readCache: ({required bool fromFetch}) async {
        final cached = await _readCachedFeed();
        if (cached != null || fromFetch) return cached;
        return fetchRecentNotifications(fromGet: true);
      },
    );
  }

  Future<NotificationsFeed?> getRecentNotifications({
    bool fromFetch = false,
  }) async {
    final cached = await _readCachedFeed();
    if (cached != null || fromFetch) return cached;
    return fetchRecentNotifications(fromGet: true);
  }

  Future<ConnectNotificationDetail> fetchNotificationDetail(int id) async {
    final response = await _client.authenticatedGet(
      '${ApiConfig.connectApiBase}${ApiConfig.notificationViewPath(id)}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification detail response');
    }
    return ConnectNotificationDetail.fromJson(decoded);
  }

  Future<NotificationsFeed?> markAllSeen() async {
    final cached = await _readCachedFeed();
    if (cached == null) return null;
    final updated = cached.copyWith(
      newCount: 0,
      items: cached.items
          .map(
            (item) => item.seen
                ? item
                : RecentConnectNotification(
                    id: item.id,
                    title: item.title,
                    module: item.module,
                    link: item.link,
                    createdOn: item.createdOn,
                    expireAt: item.expireAt,
                    seen: true,
                  ),
          )
          .toList(),
    );
    await SembastCache().setJson(_cacheKey, _feedToJson(updated));
    return updated;
  }

  Future<NotificationsFeed?> _readCachedFeed() async {
    return readCachedSembastJsonMapWithFallback<NotificationsFeed>(
      key: _cacheKey,
      fromFetch: true,
      decoder: NotificationsFeed.fromJson,
      onCacheMiss: () async => null,
    );
  }

  Map<String, dynamic> _feedToJson(NotificationsFeed feed) {
    return <String, dynamic>{
      'new': feed.newCount,
      'items': feed.items
          .map(
            (item) => <String, dynamic>{
              'id': item.id,
              'title': item.title,
              'module': item.module,
              'link': item.link,
              'createdOn': item.createdOn?.toIso8601String(),
              'expireAt': item.expireAt?.toIso8601String(),
              'seen': item.seen,
            },
          )
          .toList(),
    };
  }
}

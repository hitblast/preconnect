import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<NotificationsFeed?> _future;
  NotificationsFeed? _lastFeed;

  @override
  void initState() {
    super.initState();
    _future = NotificationService().getRecentNotifications();
  }

  Future<void> _refresh() async {
    final next = NotificationService().fetchRecentNotifications();
    setState(() {
      _future = next;
    });
    final refreshed = await next;
    if (!mounted) return;
    setState(() {
      _lastFeed = refreshed;
    });
    RefreshBus.instance.notify(reason: 'notifications');
  }

  Future<void> _markAllSeen() async {
    final updated = await NotificationService().markAllSeen();
    if (!mounted) return;
    setState(() {
      _lastFeed = updated ?? _lastFeed;
    });
    RefreshBus.instance.notify(reason: 'notifications');
    showAppSnackBar(
      context,
      updated == null
          ? 'No notifications available to mark as seen.'
          : 'All notifications marked as seen.',
    );
  }

  Future<void> _openNotification(RecentConnectNotification item) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NotificationDetailPanel(notificationId: item.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Notifications',
      subtitle: 'Recent Alerts',
      icon: Icons.notifications_outlined,
      actions: [
        _HeaderActionButton(
          icon: Icons.done_all_rounded,
          onTap: () {
            _markAllSeen();
          },
        ),
      ],
      body: FutureBuilder<NotificationsFeed?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuLoading(),
            );
          }

          final feed = _lastFeed ?? snapshot.data;
          final items = feed?.items ?? const <RecentConnectNotification>[];
          if (items.isEmpty) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuEmptyState(
                message: 'No recent notifications found.',
              ),
            );
          }

          final groupedItems = _groupItemsByDate(items);

          return BracuRefreshScroll(
            onRefresh: _refresh,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...groupedItems.entries.map(
                  (entry) => _NotificationDaySection(
                    label: _dayLabel(entry.key),
                    dateLabel: _dateLabel(entry.key),
                    children: entry.value
                        .map(
                          (item) => _NotificationCard(
                            item: item,
                            onTap: () => _openNotification(item),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<DateTime, List<RecentConnectNotification>> _groupItemsByDate(
    List<RecentConnectNotification> items,
  ) {
    final grouped = <DateTime, List<RecentConnectNotification>>{};
    for (final item in items) {
      final local = item.createdOn?.toLocal();
      final key = local == null
          ? DateTime(1970)
          : DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(key, () => <RecentConnectNotification>[]).add(item);
    }
    return grouped;
  }

  String _dayLabel(DateTime date) {
    if (date.year == 1970) return 'Unknown';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    return DateFormat('EEEE').format(date);
  }

  String _dateLabel(DateTime date) {
    if (date.year == 1970) return '';
    return DateFormat('d MMMM, yyyy').format(date);
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: BracuPalette.primary),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final RecentConnectNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final createdLabel = _formatTime(item.createdOn);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: BracuCard(
          isHighlighted: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? 'Untitled notification' : item.title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _moduleLabel(item.module),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (createdLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              createdLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _moduleLabel(String raw) {
    final cleaned = raw.trim().toLowerCase();
    switch (cleaned) {
      case 'fin':
        return 'Finance';
      case 'adv':
        return 'Advising';
      case 'reg':
        return 'Registration';
      default:
        return cleaned.isEmpty ? 'General' : cleaned.toUpperCase();
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return DateFormat('h:mm a').format(local);
  }
}

class _NotificationDaySection extends StatelessWidget {
  const _NotificationDaySection({
    required this.label,
    required this.dateLabel,
    required this.children,
  });

  final String label;
  final String dateLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _NotificationDetailPanel extends StatefulWidget {
  const _NotificationDetailPanel({required this.notificationId});

  final int notificationId;

  @override
  State<_NotificationDetailPanel> createState() =>
      _NotificationDetailPanelState();
}

class _NotificationDetailPanelState extends State<_NotificationDetailPanel> {
  late final Future<ConnectNotificationDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationService().fetchNotificationDetail(
      widget.notificationId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Material(
            color: BracuPalette.card(context),
            child: FutureBuilder<ConnectNotificationDetail>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 320,
                    child: Center(child: BracuLoading()),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return SizedBox(
                    height: 320,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Unable to load notification details.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: BracuPalette.textPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Pull to refresh the list and try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final detail = snapshot.data!;
                final formattedDetails = _formatNotificationDetails(
                  detail.details,
                );
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: BracuPalette.textSecondary(
                                context,
                              ).withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                detail.title.isEmpty
                                    ? 'Notification'
                                    : detail.title,
                                style: TextStyle(
                                  color: BracuPalette.textPrimary(context),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _detailMeta(detail),
                          style: TextStyle(
                            color: BracuPalette.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          formattedDetails.isEmpty
                              ? 'No additional details were provided.'
                              : formattedDetails,
                          style: TextStyle(
                            color: BracuPalette.textPrimary(context),
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _moduleLabel(String raw) {
    final cleaned = raw.trim().toLowerCase();
    switch (cleaned) {
      case 'fin':
        return 'Finance';
      case 'adv':
        return 'Advising';
      case 'reg':
        return 'Registration';
      case 'exc':
        return 'Exam & Course';
      default:
        return cleaned.isEmpty ? 'General' : cleaned.toUpperCase();
    }
  }

  String _detailMeta(ConnectNotificationDetail detail) {
    final module = _moduleLabel(detail.module);
    final createdOn = detail.createdOn;
    if (createdOn == null) return module;
    final fullTime = DateFormat(
      'EEEE, d MMMM yyyy, h:mm:ss a',
    ).format(createdOn.toLocal());
    return '$module  •  $fullTime';
  }

  String _formatNotificationDetails(String raw) {
    if (raw.trim().isEmpty) return '';

    var text = raw
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<\s*p[^>]*>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'</\s*(div|blockquote|li)\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<\s*(div|blockquote|ul|ol|li)[^>]*>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'</?\s*(b|strong|i|em|u)\s*>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');

    const htmlEntities = <String, String>{
      '&nbsp;': ' ',
      '&amp;': '&',
      '&quot;': '"',
      '&#39;': "'",
      '&lt;': '<',
      '&gt;': '>',
    };
    htmlEntities.forEach((key, value) {
      text = text.replaceAll(key, value);
    });

    text = text
        .replaceAllMapped(
          RegExp(r'([A-Za-z])(\d)'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'(\d)([A-Za-z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();

    return text;
  }
}

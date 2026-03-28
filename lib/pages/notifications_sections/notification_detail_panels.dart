import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/pages/notifications_sections/notification_list_widgets.dart';
import 'package:preconnect/pages/notifications_sections/notification_text_formatter.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

class ScraperNotificationDetailPanel extends StatelessWidget {
  const ScraperNotificationDetailPanel({super.key, required this.item});

  final NotificationListItem item;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final cleanedDetails = cleanNotificationBodyText(
      item.details,
      title: item.title,
    );
    final parts = splitNotificationBodyParts(cleanedDetails);
    final published = item.createdOn == null
        ? item.module
        : '${item.module}  •  ${DateFormat('EEEE, d MMMM yyyy, h:mm a').format(item.createdOn!.toLocal())}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Material(
            color: BracuPalette.card(context),
            child: ConstrainedBox(
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
                            item.title.isEmpty ? 'Notification' : item.title,
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
                      published,
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((item.imageUrl ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedImage(
                            url: item.imageUrl!.trim(),
                            fit: BoxFit.cover,
                            placeholder: Container(
                              color: BracuPalette.primary.withValues(
                                alpha: 0.08,
                              ),
                            ),
                            error: Container(
                              color: BracuPalette.primary.withValues(
                                alpha: 0.08,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      parts.body.isEmpty
                          ? 'No additional details were provided.'
                          : parts.body,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (parts.links.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Source links:',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...parts.links.map(
                        (link) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () async {
                                await openExternalUrl(context, link);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 2,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                alignment: Alignment.centerLeft,
                              ),
                              child: Text(
                                displayLinkLabel(link),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if ((item.url ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await openExternalUrl(context, item.url!);
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open Source'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConnectNotificationDetailPanel extends StatefulWidget {
  const ConnectNotificationDetailPanel({
    super.key,
    required this.notificationId,
  });

  final int notificationId;

  @override
  State<ConnectNotificationDetailPanel> createState() =>
      _ConnectNotificationDetailPanelState();
}

class _ConnectNotificationDetailPanelState
    extends State<ConnectNotificationDetailPanel> {
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
                final formattedDetails = cleanNotificationBodyText(
                  detail.details,
                  title: detail.title,
                );
                final parts = splitNotificationBodyParts(formattedDetails);
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
                          parts.body.isEmpty
                              ? 'No additional details were provided.'
                              : parts.body,
                          style: TextStyle(
                            color: BracuPalette.textPrimary(context),
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (parts.links.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Source links:',
                            style: TextStyle(
                              color: BracuPalette.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...parts.links.map(
                            (link) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () async {
                                    await openExternalUrl(context, link);
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 0,
                                      vertical: 2,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    alignment: Alignment.centerLeft,
                                  ),
                                  child: Text(
                                    displayLinkLabel(link),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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
}

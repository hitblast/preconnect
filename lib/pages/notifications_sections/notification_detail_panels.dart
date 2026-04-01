import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/pages/notifications_sections/notification_list_widgets.dart';
import 'package:preconnect/pages/notifications_sections/notification_text_formatter.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

class ScraperNotificationDetailPanel extends StatefulWidget {
  const ScraperNotificationDetailPanel({super.key, required this.item});

  final NotificationListItem item;

  @override
  State<ScraperNotificationDetailPanel> createState() =>
      _ScraperNotificationDetailPanelState();
}

class _ScraperNotificationDetailPanelState
    extends State<ScraperNotificationDetailPanel> {
  late final PageController _imageController;
  Timer? _autoPlayTimer;
  int _activeImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _imageController = PageController();
    _startAutoPlayIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ScraperNotificationDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_resolvedImageUrls().length != _resolvedImageUrls(oldWidget).length) {
      _autoPlayTimer?.cancel();
      _activeImageIndex = 0;
      _startAutoPlayIfNeeded();
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _imageController.dispose();
    super.dispose();
  }

  List<String> _resolvedImageUrls([ScraperNotificationDetailPanel? panel]) {
    final item = (panel ?? widget).item;
    if (item.imageUrls.isNotEmpty) return item.imageUrls;
    final fallback = (item.imageUrl ?? '').trim();
    if (fallback.isEmpty) return const <String>[];
    return <String>[fallback];
  }

  void _startAutoPlayIfNeeded() {
    final imageUrls = _resolvedImageUrls();
    if (imageUrls.length < 2) return;
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_imageController.hasClients) return;
      final next = (_activeImageIndex + 1) % imageUrls.length;
      _imageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dragController = bracuBottomSheetScrollController(context);
    final cleanedDetails = cleanNotificationBodyText(
      widget.item.details,
      title: widget.item.title,
    );
    final parts = splitNotificationBodyParts(cleanedDetails);
    final imageUrls = _resolvedImageUrls();
    final published = widget.item.createdOn == null
        ? widget.item.module
        : '${widget.item.module}  •  ${DateFormat('EEEE, d MMMM yyyy, h:mm a').format(widget.item.createdOn!.toLocal())}';
    return bracuBottomSheetSurface(
      context,
      child: SingleChildScrollView(
        controller: dragController,
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
                    widget.item.title.isEmpty
                        ? 'Notification'
                        : widget.item.title,
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
            if (imageUrls.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      if (imageUrls.length == 1)
                        CachedImage(
                          url: imageUrls.first,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            color: BracuPalette.primary.withValues(alpha: 0.08),
                          ),
                          error: Container(
                            color: BracuPalette.primary.withValues(alpha: 0.08),
                          ),
                        )
                      else
                        PageView.builder(
                          controller: _imageController,
                          itemCount: imageUrls.length,
                          onPageChanged: (index) {
                            if (!mounted) return;
                            setState(() {
                              _activeImageIndex = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            return CachedImage(
                              url: imageUrls[index],
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
                            );
                          },
                        ),
                      if (imageUrls.length >= 2)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 10,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(imageUrls.length, (
                                    index,
                                  ) {
                                    final isActive = index == _activeImageIndex;
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      width: isActive ? 14 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? Colors.white
                                            : Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
            if ((widget.item.url ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await openExternalUrl(context, widget.item.url!);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Source'),
                ),
              ),
            ],
          ],
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
    final dragController = bracuBottomSheetScrollController(context);
    return bracuBottomSheetSurface(
      context,
      child: FutureBuilder<ConnectNotificationDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: BracuLoading());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
            );
          }

          final detail = snapshot.data!;
          final formattedDetails = cleanNotificationBodyText(
            detail.details,
            title: detail.title,
          );
          final parts = splitNotificationBodyParts(formattedDetails);
          return SingleChildScrollView(
            controller: dragController,
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
                        detail.title.isEmpty ? 'Notification' : detail.title,
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
              ],
            ),
          );
        },
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

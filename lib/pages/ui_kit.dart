import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:native_file_preview/native_file_preview.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/tools/web_pdf_opener.dart';
import 'package:url_launcher/url_launcher.dart';

String formatDate(String? input) {
  if (input == null || input.trim().isEmpty) return '';
  final raw = input.trim();
  final candidates = <DateFormat>[
    DateFormat('yyyy-MM-dd'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('yyyy.MM.dd'),
    DateFormat('dd-MM-yyyy'),
    DateFormat('dd/MM/yyyy'),
    DateFormat('d/M/yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('d MMM, yyyy'),
    DateFormat('d-MMM-yyyy'),
    DateFormat('MMM d, yyyy'),
  ];

  DateTime? dt;
  for (final f in candidates) {
    try {
      dt = f.parseStrict(raw);
      break;
    } catch (_) {}
  }
  dt ??= DateTime.tryParse(raw);
  if (dt == null) return raw;
  return DateFormat('d MMMM, y').format(dt);
}

String formatTime(String? input) {
  return BracuTime.format(input);
}

String formatTimeRange(String? start, String? end) {
  return BracuTime.range(start, end);
}

String formatLongDate(DateTime date) {
  return DateFormat('d MMMM, yyyy').format(date);
}

String formatRelativeDayLabel(
  DateTime date, {
  bool includeYesterday = false,
  bool includeTomorrow = false,
  String? unknownLabel,
}) {
  if (unknownLabel != null && date.year == 1970) return unknownLabel;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  if (target == today) return 'Today';
  if (includeYesterday &&
      target == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  if (includeTomorrow && target == today.add(const Duration(days: 1))) {
    return 'Tomorrow';
  }
  return DateFormat('EEEE').format(date);
}

String formatDateTimeLabel(DateTime dateTime, {String separator = ' • '}) {
  return '${formatLongDate(dateTime)}$separator${BracuTime.formatDateTime(dateTime)}';
}

void copyToClipboard(BuildContext context, String text) {
  final value = text.trim();
  if (value.isEmpty) return;
  Clipboard.setData(ClipboardData(text: value));
  showAppSnackBar(context, 'Copied to clipboard');
}

Future<bool> openExternalUrl(
  BuildContext context,
  String rawUrl, {
  String failureMessage = 'Unable to open link.',
  LaunchMode mobilePreferredMode = LaunchMode.inAppBrowserView,
  LaunchMode mobileFallbackMode = LaunchMode.externalApplication,
}) async {
  final url = rawUrl.trim();
  if (url.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final mode = kIsWeb ? LaunchMode.platformDefault : mobilePreferredMode;
  var launched = await launchUrl(uri, mode: mode);
  if (!launched && !kIsWeb) {
    launched = await launchUrl(uri, mode: mobileFallbackMode);
  }
  if (!launched && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return launched;
}

Future<bool> openMailComposer(
  BuildContext context,
  String email, {
  String failureMessage = 'Unable to open email compose',
}) async {
  final cleaned = email.trim();
  if (cleaned.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final mailtoUri = Uri(scheme: 'mailto', path: cleaned);
  final openedMail = await launchUrl(
    mailtoUri,
    mode: LaunchMode.platformDefault,
  );
  if (!openedMail && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return openedMail;
}

DateTime? _lastSnackAt;
String? _lastSnackMessage;
Timer? _snackAutoTimer;
final NativeFilePreview _nativeFilePreview = NativeFilePreview();

void showAppSnackBar(BuildContext context, String message) {
  if (kIsWeb) return;
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;
  final now = DateTime.now();
  if (_lastSnackMessage == trimmed &&
      _lastSnackAt != null &&
      now.difference(_lastSnackAt!) < const Duration(milliseconds: 1200)) {
    return;
  }
  _lastSnackMessage = trimmed;
  _lastSnackAt = now;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final messenger = ScaffoldMessenger.of(context);
  _snackAutoTimer?.cancel();
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(trimmed, style: const TextStyle(color: Colors.white)),
      backgroundColor: isDark ? const Color(0xFF1E6BE3) : BracuPalette.primary,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      action: SnackBarAction(
        label: 'Close',
        textColor: Colors.white,
        onPressed: () {
          messenger.hideCurrentSnackBar();
        },
      ),
    ),
  );
  _snackAutoTimer = Timer(const Duration(seconds: 3), () {
    messenger.hideCurrentSnackBar();
  });
}

Future<void> openGradeSheet(BuildContext context) async {
  try {
    if (kIsWeb) {
      final bytes = await GradeSheetService().fetchGradeSheetBytes(fromGet: true);
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        showAppSnackBar(context, 'Could not fetch the latest grade sheet');
        return;
      }
      final fileName = await GradeSheetService().gradeSheetFileName();
      await openPdfInBrowser(bytes: bytes, fileName: '$fileName.pdf');
      return;
    }

    final gradeSheet = await GradeSheetService().fetchGradeSheet(fromGet: true);
    if (!context.mounted) return;
    if (gradeSheet == null) {
      showAppSnackBar(context, 'Could not fetch the latest grade sheet');
      return;
    }
    await _nativeFilePreview.previewFile(gradeSheet.file.path);
  } on PlatformException catch (error) {
    if (!context.mounted) return;
    final message = switch (error.code) {
      'NO_APP_FOUND' => 'No app found to open this PDF.',
      'FILE_NOT_FOUND' => 'The PDF file was not found.',
      _ => error.message ?? 'Could not open the PDF.',
    };
    showAppSnackBar(context, message);
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(context, 'Could not open the PDF.');
  }
}

String normalizeWeekday(String? day) {
  if (day == null) return '';
  final trimmed = day.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.toUpperCase();
}

String formatWeekdayTitle(String? day) {
  final normalized = normalizeWeekday(day);
  switch (normalized) {
    case 'MONDAY':
      return 'Monday';
    case 'TUESDAY':
      return 'Tuesday';
    case 'WEDNESDAY':
      return 'Wednesday';
    case 'THURSDAY':
      return 'Thursday';
    case 'FRIDAY':
      return 'Friday';
    case 'SATURDAY':
      return 'Saturday';
    case 'SUNDAY':
      return 'Sunday';
    default:
      if (day == null || day.trim().isEmpty) return '';
      final lower = day.trim().toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
  }
}

String formatSemesterTitle(String? raw) {
  if (raw == null) return '';
  final cleaned = raw.trim();
  if (cleaned.isEmpty || cleaned == 'N/A' || cleaned == '-') return '';
  final normalized = cleaned.replaceAll(RegExp(r'[_-]+'), ' ');
  final parts = normalized.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final titled = parts
      .map((part) {
        if (RegExp(r'^\d+$').hasMatch(part)) return part;
        final lower = part.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
  return titled;
}

String formatSemesterFromSessionIdInt(int semesterSessionId) {
  final year = semesterSessionId ~/ 10;
  final code = semesterSessionId % 10;
  final label = switch (code) {
    1 => 'Spring',
    2 => 'Fall',
    3 => 'Summer',
    _ => 'Session',
  };
  return '$label $year';
}

String formatSemesterFromSessionId(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty || cleaned == 'N/A' || cleaned == '-') return '';
  final value = int.tryParse(cleaned);
  if (value == null) return formatSemesterTitle(cleaned);
  return formatSemesterFromSessionIdInt(value);
}

String formatTimeHour(String? input) {
  final t = formatTime(input);
  if (t.isEmpty) return '--';
  return t.split(':').first;
}

double compactPopupMenuWidth(
  BuildContext context,
  List<String> labels, {
  double minWidth = 0,
  double maxWidth = 320,
  TextStyle style = const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  double horizontalPadding = 16,
  double screenMargin = 20,
}) {
  var maxTextWidth = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    if (painter.width > maxTextWidth) {
      maxTextWidth = painter.width;
    }
  }
  final screenMax = MediaQuery.sizeOf(context).width - screenMargin;
  final effectiveMax = math.min(maxWidth, screenMax);
  return (maxTextWidth + (horizontalPadding * 2) + 4).clamp(
    minWidth,
    effectiveMax,
  );
}

PopupMenuItem<T> compactPopupMenuItem<T>({
  required T value,
  required String label,
  double height = 42,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  TextStyle textStyle = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  ),
}) {
  return PopupMenuItem<T>(
    value: value,
    padding: padding,
    height: height,
    child: Text(
      label,
      style: textStyle,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    ),
  );
}

class BracuSelectOption<T> {
  const BracuSelectOption({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
}

Future<T?> showBracuSelectSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<BracuSelectOption<T>> options,
  T? selectedValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: BracuPalette.card(context),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final textPrimary = BracuPalette.textPrimary(sheetContext);
      final textSecondary = BracuPalette.textSecondary(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textSecondary.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle.trim(),
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: Icon(Icons.close_rounded, color: textSecondary),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = option.value == selectedValue;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () =>
                              Navigator.of(sheetContext).pop(option.value),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? BracuPalette.primary.withValues(alpha: 0.12)
                                  : BracuPalette.card(sheetContext)
                                        .withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selected
                                    ? BracuPalette.primary.withValues(alpha: 0.70)
                                    : textSecondary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? BracuPalette.primary.withValues(
                                            alpha: 0.14,
                                          )
                                        : textSecondary.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    option.icon ??
                                        (selected
                                            ? Icons.check_rounded
                                            : Icons.tune_rounded),
                                    size: 18,
                                    color: selected
                                        ? BracuPalette.primary
                                        : textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.label,
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (option.subtitle != null &&
                                          option.subtitle!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          option.subtitle!.trim(),
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.chevron_right_rounded,
                                  size: selected ? 20 : 18,
                                  color: selected
                                      ? BracuPalette.primary
                                      : textSecondary.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

void attemptScrollToHighlightedKey({
  required GlobalKey? highlightKey,
  required bool hasRetried,
  required VoidCallback retry,
  required VoidCallback onScrolled,
  double alignment = 0.5,
  Duration duration = const Duration(milliseconds: 450),
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = highlightKey?.currentContext;
    if (context == null) {
      if (!hasRetried) {
        retry();
      }
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
    onScrolled();
  });
}

class BracuSelectChip extends StatelessWidget {
  const BracuSelectChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.showArrow = true,
    this.compact = false,
    this.borderRadius = 18,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool compact;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final primaryColor = selected ? BracuPalette.primary : textSecondary;
    final backgroundColor = compact
        ? (selected
              ? BracuPalette.primary.withValues(alpha: 0.14)
              : BracuPalette.card(context).withValues(alpha: 0.94))
        : BracuPalette.card(context).withValues(alpha: 0.94);
    final borderColor = selected
        ? BracuPalette.primary.withValues(alpha: compact ? 0.45 : 0.70)
        : textSecondary.withValues(alpha: 0.26);
    final horizontalPadding = compact ? 14.0 : 16.0;
    final verticalPadding = compact ? 10.0 : 11.0;
    final resolvedRadius = compact ? 16.0 : borderRadius;
    final labelStyle = TextStyle(
      color: BracuPalette.textPrimary(context),
      fontSize: compact ? 13 : 14,
      fontWeight: FontWeight.w700,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(resolvedRadius),
      child: Container(
        margin: compact ? null : const EdgeInsets.only(left: 8),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(resolvedRadius),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 17 : 18, color: primaryColor),
              const SizedBox(width: 8),
            ],
            Text(label, style: labelStyle),
            if (showArrow) ...[
              SizedBox(width: compact ? 6 : 8),
              Icon(
                Icons.expand_more_rounded,
                size: compact ? 18 : 20,
                color: primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatSectionBadge(String? sectionName) {
  if (sectionName == null) return '?';
  final trimmed = sectionName.trim();
  if (trimmed.isEmpty) return '?';
  final match = RegExp(r'\d+').firstMatch(trimmed);
  if (match == null) return '?';
  final number = int.tryParse(match.group(0)!);
  if (number == null) return match.group(0)!.padLeft(2, '0');
  return number.toString().padLeft(2, '0');
}

const EdgeInsets kBracuPageListPadding = EdgeInsets.fromLTRB(20, 8, 20, 28);

class BracuRefreshList extends StatefulWidget {
  const BracuRefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.controller,
    this.padding = kBracuPageListPadding,
  });

  final RefreshCallback onRefresh;
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  State<BracuRefreshList> createState() => _BracuRefreshListState();
}

class _BracuRefreshListState extends State<BracuRefreshList> {
  ScrollController? _internalController;
  bool _showScrollTop = false;

  ScrollController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null ? ScrollController() : null;
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant BracuRefreshList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onScroll);
    _internalController?.removeListener(_onScroll);
    if (oldWidget.controller == null && widget.controller != null) {
      _internalController?.dispose();
      _internalController = null;
    } else if (oldWidget.controller != null && widget.controller == null) {
      _internalController = ScrollController();
    }
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _internalController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final shouldShow = _controller.offset > 360;
    if (shouldShow == _showScrollTop) return;
    setState(() {
      _showScrollTop = shouldShow;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            children: widget.children,
          ),
        ),
        _BracuScrollTopButton(visible: _showScrollTop, onTap: _scrollToTop),
      ],
    );
  }
}

class BracuRefreshListBuilder extends StatefulWidget {
  const BracuRefreshListBuilder({
    super.key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding = kBracuPageListPadding,
  });

  final RefreshCallback onRefresh;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  State<BracuRefreshListBuilder> createState() =>
      _BracuRefreshListBuilderState();
}

class _BracuRefreshListBuilderState extends State<BracuRefreshListBuilder> {
  ScrollController? _internalController;
  bool _showScrollTop = false;

  ScrollController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null ? ScrollController() : null;
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant BracuRefreshListBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onScroll);
    _internalController?.removeListener(_onScroll);
    if (oldWidget.controller == null && widget.controller != null) {
      _internalController?.dispose();
      _internalController = null;
    } else if (oldWidget.controller != null && widget.controller == null) {
      _internalController = ScrollController();
    }
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _internalController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final shouldShow = _controller.offset > 360;
    if (shouldShow == _showScrollTop) return;
    setState(() {
      _showScrollTop = shouldShow;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.builder(
            controller: _controller,
            padding: widget.padding,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          ),
        ),
        _BracuScrollTopButton(visible: _showScrollTop, onTap: _scrollToTop),
      ],
    );
  }
}

class BracuRefreshPlaceholder extends StatelessWidget {
  const BracuRefreshPlaceholder({
    super.key,
    required this.onRefresh,
    required this.child,
    this.topSpacing = 160,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return BracuRefreshList(
      onRefresh: onRefresh,
      children: [
        SizedBox(height: topSpacing),
        child,
      ],
    );
  }
}

Widget buildRefreshLoadingState({
  required RefreshCallback onRefresh,
  String label = 'Loading...',
  double topSpacing = 0,
}) {
  return BracuRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: BracuLoading(label: label),
  );
}

Widget buildRefreshErrorState({
  required RefreshCallback onRefresh,
  required Object? error,
  double topSpacing = 0,
}) {
  return BracuRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: BracuEmptyState(message: 'Error: $error'),
  );
}

Widget buildRefreshEmptyState({
  required RefreshCallback onRefresh,
  required String message,
  double topSpacing = 0,
}) {
  return BracuRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: BracuEmptyState(message: message),
  );
}

class BracuRefreshScroll extends StatefulWidget {
  const BracuRefreshScroll({
    super.key,
    required this.onRefresh,
    required this.child,
    this.padding = kBracuPageListPadding,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final EdgeInsets padding;

  @override
  State<BracuRefreshScroll> createState() => _BracuRefreshScrollState();
}

class _BracuRefreshScrollState extends State<BracuRefreshScroll> {
  final ScrollController _controller = ScrollController();
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final shouldShow = _controller.offset > 360;
    if (shouldShow == _showScrollTop) return;
    setState(() {
      _showScrollTop = shouldShow;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: SingleChildScrollView(
            controller: _controller,
            padding: widget.padding,
            physics: const AlwaysScrollableScrollPhysics(),
            child: widget.child,
          ),
        ),
        _BracuScrollTopButton(visible: _showScrollTop, onTap: _scrollToTop),
      ],
    );
  }
}

class _BracuScrollTopButton extends StatelessWidget {
  const _BracuScrollTopButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16 + MediaQuery.of(context).padding.bottom,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: BracuPalette.textPrimary(context),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BracuPalette {
  static const Color bgTopLight = Color(0xFFEAF4FF);
  static const Color bgBottomLight = Color(0xFFF3FFF4);
  static const Color primary = Color(0xFF1E6BE3);
  static const Color accent = Color(0xFF22B573);
  static const Color info = Color(0xFF2C9DFF);
  static const Color warning = Color(0xFFEF6C35);
  static const Color favorite = Color(0xFFFFA726);
  static const Color danger = Color(0xFFD63B3B);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Colors.black;

  static bool _isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color bgTop(BuildContext context) {
    return _isDark(context) ? Colors.black : bgTopLight;
  }

  static Color bgBottom(BuildContext context) {
    return _isDark(context) ? Colors.black : bgBottomLight;
  }

  static Color card(BuildContext context) {
    return _isDark(context) ? cardDark : cardLight;
  }

  static Color textPrimary(BuildContext context) {
    return _isDark(context) ? Colors.white : Colors.black87;
  }

  static Color textSecondary(BuildContext context) {
    return _isDark(context) ? Colors.white70 : Colors.black54;
  }
}

class BracuPageScaffold extends StatelessWidget {
  const BracuPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.actions = const [],
    this.showMenu = false,
    this.showBack = true,
    this.onHeaderTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;
  final bool showMenu;
  final bool showBack;
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BracuPalette.bgTop(context),
              BracuPalette.bgBottom(context),
            ],
          ),
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: -70,
                    right: -60,
                    child: DecorBlob(
                      color: BracuPalette.primary.withValues(alpha: 0.12),
                      size: 200,
                    ),
                  ),
                  Positioned(
                    bottom: -80,
                    left: -70,
                    child: DecorBlob(
                      color: BracuPalette.accent.withValues(alpha: 0.10),
                      size: 220,
                    ),
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: showBack
                            ? const EdgeInsets.fromLTRB(6, 12, 20, 8)
                            : const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: _PageHeader(
                          title: title,
                          subtitle: subtitle,
                          icon: icon,
                          actions: actions,
                          showMenu: showMenu,
                          showBack: showBack,
                          onHeaderTap: onHeaderTap,
                        ),
                      ),
                      Expanded(child: body),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.showMenu,
    required this.showBack,
    this.onHeaderTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;
  final bool showMenu;
  final bool showBack;
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    final canPop = navigator?.canPop() ?? false;
    final backScope = BracuBackScope.maybeOf(context);
    final canScopeBack = backScope?.canGoBack ?? false;
    final hasBack = showBack && (canPop || canScopeBack);
    final row = Row(
      children: [
        if (showMenu) const SizedBox(width: 0, height: 0),
        if (hasBack)
          Transform.translate(
            offset: const Offset(-2, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (canPop && navigator != null) {
                  navigator.maybePop();
                  return;
                }
                backScope?.onBack();
              },
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 28,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ),
          ),
        Transform.translate(
          offset: hasBack ? const Offset(-4, 0) : Offset.zero,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: BracuPalette.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
        ...actions,
      ],
    );
    if (onHeaderTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onHeaderTap,
      child: row,
    );
  }
}

class BracuCard extends StatelessWidget {
  const BracuCard({
    super.key,
    required this.child,
    this.isHighlighted = false,
    this.highlightColor,
  });

  final Widget child;
  final bool isHighlighted;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final highlight = highlightColor ?? BracuPalette.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBorderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.22 : 0.16);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted
              ? highlight.withValues(alpha: isDark ? 0.7 : 0.9)
              : baseBorderColor,
          width: isHighlighted ? 1.6 : 1,
        ),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const []
            : [
                BoxShadow(
                  color: isHighlighted
                      ? highlight.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.06),
                  blurRadius: isHighlighted ? 20 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

class BracuSectionTitle extends StatelessWidget {
  const BracuSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BracuPalette.textPrimary(context),
      ),
    );
  }
}

class BracuLoading extends StatelessWidget {
  const BracuLoading({super.key, this.label = 'Loading...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: BracuPalette.primary,
              ),
            ),
            if (label.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: BracuPalette.textSecondary(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BracuEmptyState extends StatelessWidget {
  const BracuEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: BracuPalette.textSecondary(context)),
      ),
    );
  }
}

class DecorBlob extends StatelessWidget {
  const DecorBlob({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }
}

class BracuBackScope extends InheritedWidget {
  const BracuBackScope({
    super.key,
    required this.canGoBack,
    required this.onBack,
    required super.child,
  });

  final bool canGoBack;
  final VoidCallback onBack;

  static BracuBackScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BracuBackScope>();
  }

  @override
  bool updateShouldNotify(BracuBackScope oldWidget) {
    return canGoBack != oldWidget.canGoBack;
  }
}

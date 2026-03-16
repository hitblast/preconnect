import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:native_file_preview/native_file_preview.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/cgpa_calculator.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/refresh_bus.dart';
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

void showAppSnackBar(
  BuildContext context,
  String message, {
  String actionLabel = 'Close',
  VoidCallback? onAction,
}) {
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
        label: actionLabel,
        textColor: Colors.white,
        onPressed: () {
          if (onAction != null) {
            onAction();
            messenger.hideCurrentSnackBar();
            return;
          }
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

List<section.Section> buildCurrentSectionsForCalculator(
  ProgressInfo info,
  String? scheduleJson,
) {
  final sections = section.parseSectionsFromScheduleJson(scheduleJson);
  final courseTitleByCode = <String, String>{};
  for (final course in info.curriculumCourses) {
    final code = course.code.trim().toUpperCase();
    final title = course.title.trim();
    if (code.isEmpty || title.isEmpty) continue;
    courseTitleByCode[code] = title;
  }
  for (final course in info.completedCourses) {
    final code = course.code.trim().toUpperCase();
    final title = course.title.trim();
    if (code.isEmpty || title.isEmpty) continue;
    courseTitleByCode.putIfAbsent(code, () => title);
  }
  return sections.where((current) {
    final resolvedTitle =
        (courseTitleByCode[current.courseCode.trim().toUpperCase()] ??
                (current.name ?? ''))
            .trim();
    final hasNoRealName =
        resolvedTitle.isEmpty ||
        resolvedTitle.toUpperCase() == current.courseCode.trim().toUpperCase();
    return !(current.courseCredit <= 0 && hasNoRealName);
  }).toList();
}

Future<void> openCgpaCalculatorPage(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: const Text(
        'Loading...',
        style: TextStyle(color: Colors.white),
      ),
      backgroundColor: BracuPalette.primary,
      duration: const Duration(seconds: 20),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );

  try {
    final info = await ProgressService().getProgress();
    final profile = await ProfileService().getProfile();
    final scheduleJson = await ScheduleService().getStudentSchedule();
    if (!context.mounted) return;

    if (info == null) {
      messenger.hideCurrentSnackBar();
      showAppSnackBar(
        context,
        'No progress data available for CGPA calculator',
      );
      return;
    }

    final currentCgpa = (profile?['cgpa'] ?? '').trim();
    final sections = buildCurrentSectionsForCalculator(info, scheduleJson);
    messenger.hideCurrentSnackBar();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CgpaCalculatorPage(
          info: info,
          currentSections: sections,
          currentCgpa: currentCgpa,
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    showAppSnackBar(context, 'Could not open CGPA calculator');
  }
}

const String _kPreconnectSupportQrUrl = 'https://preconnect.app/bkash-qr.jpg';
const String _kPreconnectSupportNumber = '01865493144';
const String _kPreconnectSupportReference = 'PreConnect App';
const String _kPreconnectWhatsAppUrl =
    'https://api.whatsapp.com/send?phone=8801865493144&text=Hi%20PreConnect%2C%20I%20want%20to%20become%20a%20sponsor%20for%20the%20app.';

Future<void> showBracuFundingSupportSheet(BuildContext context) async {
  await showBracuBottomSheet<void>(
    context,
    title: 'Support PreConnect',
    subtitle: 'Help fund the iOS release and future app costs',
    maxHeightFactor: 0.86,
    builder: (sheetContext, textPrimary, textSecondary) {
      return ListView(
        shrinkWrap: true,
        children: [
          Text(
            'PreConnect is student-built and stays free for everyone. Contributions help cover the Apple Developer membership and future publishing costs.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          const BracuFundingSupportContent(),
        ],
      );
    },
  );
}

class BracuActionBannerCard extends StatelessWidget {
  const BracuActionBannerCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = BracuPalette.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: BracuPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: BracuPalette.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BracuFundingSupportContent extends StatelessWidget {
  const BracuFundingSupportContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0B0B0B)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BracuPalette.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Colors.white,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth;
                  return CachedImage(
                    url: _kPreconnectSupportQrUrl,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: const Icon(Icons.qr_code_2_rounded),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          const BracuSupportNumberRow(number: _kPreconnectSupportNumber),
          const SizedBox(height: 12),
          Text(
            "We're looking for Sponsor",
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Support our iOS App Store launch',
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 13,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _BracuSponsorActionChip(
                icon: Icons.call_outlined,
                label: _kPreconnectSupportNumber,
                onTap: () => copyToClipboard(context, _kPreconnectSupportNumber),
              ),
              _BracuSponsorActionChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp',
                onTap: () => openExternalUrl(
                  context,
                  _kPreconnectWhatsAppUrl,
                  failureMessage: 'Unable to open WhatsApp.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BracuSponsorActionChip extends StatelessWidget {
  const _BracuSponsorActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: BracuPalette.textPrimary(context),
        side: BorderSide(
          color: BracuPalette.primary.withValues(alpha: 0.18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class BracuSupportNumberRow extends StatelessWidget {
  const BracuSupportNumberRow({super.key, required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  number,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: number));
                    if (context.mounted) {
                      showAppSnackBar(context, 'Number copied');
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: BracuPalette.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'bKash / Nagad / Upay',
              style: TextStyle(color: textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 220,
              child: Column(
                children: [
                  Text(
                    'Send money with reference',
                    style: TextStyle(color: textSecondary, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        _kPreconnectSupportReference,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: _kPreconnectSupportReference),
                          );
                          if (context.mounted) {
                            showAppSnackBar(context, 'Reference copied');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: BracuPalette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
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
    2 => 'Summer',
    3 => 'Fall',
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

Future<T?> showBracuBottomSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  double maxHeightFactor = 0.72,
  List<Widget> actions = const <Widget>[],
  required Widget Function(
    BuildContext sheetContext,
    Color textPrimary,
    Color textSecondary,
  )
  builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: BracuPalette.card(context),
    isScrollControlled: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final textPrimary = BracuPalette.textPrimary(sheetContext);
      final textSecondary = BracuPalette.textSecondary(sheetContext);
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(sheetContext).height * maxHeightFactor,
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
                            if (subtitle != null &&
                                subtitle.trim().isNotEmpty) ...[
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
                      ...actions,
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: Icon(Icons.close_rounded, color: textSecondary),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: builder(sheetContext, textPrimary, textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<bool> showBracuConfirmationDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  required String confirmLabel,
  Color confirmColor = BracuPalette.primary,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: BracuPalette.card(dialogContext),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: confirmColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(dialogContext),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  color: BracuPalette.textSecondary(dialogContext),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: confirmColor,
                        side: BorderSide(
                          color: confirmColor.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed == true;
}

Future<T?> showBracuSelectSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<BracuSelectOption<T>> options,
  T? selectedValue,
}) {
  return showBracuBottomSheet<T>(
    context,
    title: title,
    subtitle: subtitle,
    maxHeightFactor: 0.72,
    builder: (sheetContext, textPrimary, textSecondary) {
      return ListView.separated(
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
              onTap: () => Navigator.of(sheetContext).pop(option.value),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? BracuPalette.primary.withValues(alpha: 0.12)
                      : BracuPalette.card(sheetContext).withValues(alpha: 0.72),
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
                            ? BracuPalette.primary.withValues(alpha: 0.14)
                            : textSecondary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        option.icon ??
                            (selected ? Icons.check_rounded : Icons.tune_rounded),
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
      );
    },
  );
}

Future<T?> showBracuSelectDropdown<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<BracuSelectOption<T>> options,
  T? selectedValue,
}) async {
  final renderBox = context.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (renderBox == null || overlay == null) {
    return showBracuSelectSheet<T>(
      context,
      title: title ?? 'Select Option',
      subtitle: subtitle,
      options: options,
      selectedValue: selectedValue,
    );
  }

  final target = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
  final textPrimary = BracuPalette.textPrimary(context);
  final cardColor = BracuPalette.card(context);
  final menuTop = target.dy + renderBox.size.height + 6;
  final maxWidth = overlay.size.width - 24;
  final estimatedWidth = options.fold<double>(
    88,
    (current, option) => math.max(current, 26 + (option.label.length * 10)),
  );
  final menuWidth = estimatedWidth.clamp(88, maxWidth);
  final menuLeft = math.min(target.dx, overlay.size.width - menuWidth - 12);

  return showGeneralDialog<T>(
    context: context,
    barrierLabel: 'Dismiss',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, _) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 8),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: options.map((option) {
                      final selected = option.value == selectedValue;
                      return InkWell(
                        onTap: () => Navigator.of(dialogContext).pop(option.value),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                option.label,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: BracuPalette.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
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
    final horizontalPadding = compact ? 11.0 : 14.0;
    final verticalPadding = compact ? 8.0 : 9.0;
    final resolvedRadius = compact ? 14.0 : borderRadius;
    final labelStyle = TextStyle(
      color: BracuPalette.textPrimary(context),
      fontSize: compact ? 12 : 13,
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
              Icon(icon, size: compact ? 15 : 16, color: primaryColor),
              const SizedBox(width: 6),
            ],
            Text(label, style: labelStyle),
            if (showArrow) ...[
              SizedBox(width: compact ? 4 : 6),
              Icon(
                Icons.expand_more_rounded,
                size: compact ? 16 : 18,
                color: primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BracuSelectDropdownChip<T> extends StatelessWidget {
  const BracuSelectDropdownChip({
    super.key,
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.title,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.compact = false,
    this.borderRadius = 18,
    this.showArrow = true,
  });

  final String label;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<BracuSelectOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final bool selected;
  final bool compact;
  final double borderRadius;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (chipContext) => BracuSelectChip(
        label: label,
        icon: icon,
        selected: selected,
        compact: compact,
        borderRadius: borderRadius,
        showArrow: showArrow,
        onTap: () async {
          final value = await showBracuSelectDropdown<T>(
            chipContext,
            title: title,
            subtitle: subtitle,
            options: options,
            selectedValue: selectedValue,
          );
          if (value == null) return;
          onSelected(value);
        },
      ),
    );
  }
}

class BracuNotificationsIconButton extends StatefulWidget {
  const BracuNotificationsIconButton({
    super.key,
    required this.onTap,
    this.iconSize = 20,
    this.padding = 7,
  });

  final VoidCallback onTap;
  final double iconSize;
  final double padding;

  @override
  State<BracuNotificationsIconButton> createState() =>
      _BracuNotificationsIconButtonState();
}

class _BracuNotificationsIconButtonState
    extends State<BracuNotificationsIconButton> {
  late Future<NotificationsFeed?> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationService().getRecentNotifications();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted || !RefreshBus.instance.isReason('notifications')) return;
    setState(() {
      _future = NotificationService().getRecentNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NotificationsFeed?>(
      future: _future,
      builder: (context, snapshot) {
        final newCount = snapshot.data?.newCount ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(widget.padding),
                decoration: BoxDecoration(
                  color: BracuPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  size: widget.iconSize,
                  color: BracuPalette.primary,
                ),
              ),
            ),
            if (newCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD63B3B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    newCount > 9 ? '9+' : '$newCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class BracuSearchField extends StatelessWidget {
  const BracuSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.query = '',
    this.onClear,
    this.autofocus = false,
    this.fillAlpha = 0.92,
    this.borderRadius = 12,
    this.contentPadding,
    this.keySuffix,
  });

  final TextEditingController controller;
  final String hintText;
  final String query;
  final VoidCallback? onClear;
  final bool autofocus;
  final double fillAlpha;
  final double borderRadius;
  final EdgeInsetsGeometry? contentPadding;
  final String? keySuffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hintColor = scheme.onSurface.withValues(alpha: 0.64);
    final textColor = scheme.onSurface;
    final borderColor = scheme.onSurface.withValues(alpha: 0.24);
    return TextField(
      key: keySuffix == null
          ? null
          : ValueKey<String>(
              'bracu-search-$keySuffix-${Theme.of(context).brightness.name}',
            ),
      controller: controller,
      autofocus: autofocus,
      style: TextStyle(color: textColor),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(Icons.search, color: hintColor),
        suffixIcon: query.trim().isEmpty
            ? null
            : IconButton(
                onPressed: onClear ?? controller.clear,
                icon: Icon(Icons.close, color: hintColor),
              ),
        filled: true,
        fillColor: BracuPalette.card(context).withValues(alpha: fillAlpha),
        isDense: true,
        contentPadding: contentPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(color: scheme.primary),
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
    this.backgroundColor,
  });

  final Widget child;
  final bool isHighlighted;
  final Color? highlightColor;
  final Color? backgroundColor;

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
        color: backgroundColor ?? BracuPalette.card(context),
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

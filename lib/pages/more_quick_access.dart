import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:native_file_preview/native_file_preview.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/cgpa_calculator.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/shared_widgets/quick_access_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/web_login_setup.dart';
import 'package:preconnect/tools/web_pdf_opener.dart';

class MoreQuickAccessPage extends StatefulWidget {
  const MoreQuickAccessPage({super.key, required this.onNavigate});

  final ValueChanged<HomeTab> onNavigate;

  @override
  State<MoreQuickAccessPage> createState() => _MoreQuickAccessPageState();
}

class _MoreQuickAccessPageState extends State<MoreQuickAccessPage> {
  bool _isOpeningGradeSheet = false;

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'More',
      subtitle: 'Options',
      icon: Icons.more_horiz_rounded,
      body: ListView(
        padding: kBracuPageListPadding,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final width = (constraints.maxWidth - spacing * 2) / 3;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  QuickAccessCard(
                    width: width,
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Controls',
                    color: const Color(0xFF7C56FF),
                    onTap: () => widget.onNavigate(HomeTab.settings),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.notifications_none_rounded,
                    title: 'Updates',
                    subtitle: 'Notifications',
                    color: const Color(0xFF5B8DEF),
                    onTap: () => widget.onNavigate(HomeTab.notifications),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.calendar_today_outlined,
                    title: 'Calender',
                    subtitle: 'Events',
                    color: const Color(0xFF00A86B),
                    onTap: () => widget.onNavigate(HomeTab.calendar),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.developer_mode_outlined,
                    title: 'Devs',
                    subtitle: 'About Us',
                    color: const Color(0xFF2C9DFF),
                    onTap: () => widget.onNavigate(HomeTab.devs),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.calculate_outlined,
                    title: 'CGPA',
                    subtitle: 'Calculator',
                    color: const Color(0xFF2C9DFF),
                    onTap: () => _openCgpaCalculator(context),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Grade',
                    subtitle: 'Sheet PDF',
                    color: const Color(0xFFE53935),
                    isLoading: _isOpeningGradeSheet,
                    onTap: _isOpeningGradeSheet
                        ? () {}
                        : () async {
                            setState(() {
                              _isOpeningGradeSheet = true;
                            });
                            try {
                              await _openGradeSheet(context);
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isOpeningGradeSheet = false;
                                });
                              }
                            }
                          },
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.school_outlined,
                    title: 'Degree',
                    subtitle: 'Progress',
                    color: const Color(0xFF2C9DFF),
                    onTap: () => widget.onNavigate(HomeTab.degreeProgress),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.insights_outlined,
                    title: 'Seat',
                    subtitle: 'Status',
                    color: const Color(0xFF00A8E8),
                    onTap: () => widget.onNavigate(HomeTab.seatStatus),
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.language_rounded,
                    title: 'Web',
                    subtitle: 'Login',
                    color: const Color(0xFF1E88E5),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WebLoginSetupPage(),
                        ),
                      );
                    },
                  ),
                  QuickAccessCard(
                    width: width,
                    icon: Icons.wifi_rounded,
                    title: 'WiFi',
                    subtitle: 'Auto Login',
                    color: const Color(0xFF00A86B),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CaptiveWifiPage(),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

final NativeFilePreview _nativeFilePreview = NativeFilePreview();

Future<void> _openGradeSheet(BuildContext context) async {
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

Future<void> _openCgpaCalculator(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: const Text(
        'Loading CGPA calculator...',
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
      showAppSnackBar(context, 'No progress data available for CGPA calculator');
      return;
    }

    final currentCgpa = (profile?['cgpa'] ?? '').trim();
    final sections = _parseCurrentSemesterSections(scheduleJson);
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

List<section.Section> _parseCurrentSemesterSections(String? scheduleJson) {
  if (scheduleJson == null || scheduleJson.trim().isEmpty) {
    return const <section.Section>[];
  }
  try {
    final decoded = jsonDecode(scheduleJson);
    if (decoded is! List<dynamic>) return const <section.Section>[];
    final sections = <section.Section>[];
    final seen = <String>{};
    for (final raw in decoded.whereType<Map<String, dynamic>>()) {
      final item = section.Section.fromJson(raw);
      final key =
          '${item.sectionId}|${item.courseCode}|${item.sectionName}|${item.roomNumber}';
      if (!seen.add(key)) continue;
      sections.add(item);
    }
    sections.sort((a, b) {
      final codeCmp = compareNaturalText(a.courseCode, b.courseCode);
      if (codeCmp != 0) return codeCmp;
      return compareNaturalText(a.sectionName, b.sectionName);
    });
    return sections;
  } catch (_) {
    return const <section.Section>[];
  }
}

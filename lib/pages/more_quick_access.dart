import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:native_file_preview/native_file_preview.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/pages/captive_wifi.dart';
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
              final width = (constraints.maxWidth - spacing * 3) / 4;
              return Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
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
                      title: 'Alerts',
                      subtitle: 'Updates',
                      color: const Color(0xFF5B8DEF),
                      onTap: () => widget.onNavigate(HomeTab.notifications),
                    ),
                    QuickAccessCard(
                      width: width,
                      icon: Icons.calendar_today_outlined,
                      title: 'Events',
                      subtitle: 'Calendar',
                      color: const Color(0xFF00A86B),
                      onTap: () => widget.onNavigate(HomeTab.calendar),
                    ),
                    QuickAccessCard(
                      width: width,
                      icon: Icons.picture_as_pdf_outlined,
                      title: 'Grade',
                      subtitle: 'Sheet',
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
                ),
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

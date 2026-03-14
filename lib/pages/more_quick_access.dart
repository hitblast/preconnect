import 'package:flutter/material.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/shared_widgets/quick_access_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/web_login_setup.dart';

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
                                await openGradeSheet(context);
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
                      icon: Icons.calculate_outlined,
                      title: 'CGPA',
                      subtitle: 'Calculator',
                      color: const Color(0xFF2C9DFF),
                      onTap: () => openCgpaCalculatorPage(context),
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

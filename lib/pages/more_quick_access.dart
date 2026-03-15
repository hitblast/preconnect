import 'package:flutter/material.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/shared_widgets/quick_access_card.dart';
import 'package:preconnect/pages/ui_kit.dart';

class MoreQuickAccessPage extends StatefulWidget {
  const MoreQuickAccessPage({super.key, required this.onNavigate});

  final ValueChanged<HomeTab> onNavigate;

  @override
  State<MoreQuickAccessPage> createState() => _MoreQuickAccessPageState();
}

class _MoreQuickAccessPageState extends State<MoreQuickAccessPage> {
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
                      icon: Icons.developer_mode_outlined,
                      title: 'Devs',
                      subtitle: 'About Us',
                      color: const Color(0xFF2C9DFF),
                      onTap: () => widget.onNavigate(HomeTab.devs),
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
                      icon: Icons.school_outlined,
                      title: 'Degree',
                      subtitle: 'Progress',
                      color: const Color(0xFF2C9DFF),
                      onTap: () => widget.onNavigate(HomeTab.degreeProgress),
                    ),
                    QuickAccessCard(
                      width: width,
                      icon: Icons.computer_outlined,
                      title: 'Free',
                      subtitle: 'Labs',
                      color: const Color(0xFF00A8E8),
                      onTap: () => widget.onNavigate(HomeTab.freeLabs),
                    ),
                    QuickAccessCard(
                      width: width,
                      icon: Icons.insights_outlined,
                      title: 'Seat',
                      subtitle: 'Status',
                      color: const Color(0xFF00A8E8),
                      onTap: () => widget.onNavigate(HomeTab.seatStatus),
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

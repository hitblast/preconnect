import 'package:flutter/material.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class StudentOverviewCard extends StatelessWidget {
  const StudentOverviewCard({
    super.key,
    required this.studentId,
    required this.shortCode,
    required this.department,
    required this.currentSemester,
    required this.currentSessionSemesterId,
    required this.onOpenNotifications,
    required this.onOpenSettings,
    required this.onLogout,
    this.countdown,
  });

  final String studentId;
  final String shortCode;
  final String department;
  final String currentSemester;
  final String currentSessionSemesterId;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onLogout;
  final Widget? countdown;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = BracuPalette.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overview',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _NotificationsIconButton(onTap: onOpenNotifications),
                const SizedBox(width: 8),
                _IconButton(
                  icon: Icons.settings_outlined,
                  onTap: onOpenSettings,
                ),
                const SizedBox(width: 8),
                _IconButton(icon: Icons.logout, onTap: onLogout),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OverviewHeader(
                  isDark: isDark,
                  studentId: studentId,
                  shortCode: shortCode,
                  department: department,
                  currentSemester: currentSemester,
                  currentSessionSemesterId: currentSessionSemesterId,
                ),
                if (countdown != null) ...[
                  const SizedBox(height: 10),
                  countdown!,
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationsIconButton extends StatefulWidget {
  const _NotificationsIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_NotificationsIconButton> createState() =>
      _NotificationsIconButtonState();
}

class _NotificationsIconButtonState extends State<_NotificationsIconButton> {
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
            _IconButton(
              icon: Icons.notifications_outlined,
              onTap: widget.onTap,
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

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: BracuPalette.primary),
      ),
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({
    required this.isDark,
    required this.studentId,
    required this.shortCode,
    required this.department,
    required this.currentSemester,
    required this.currentSessionSemesterId,
  });

  final bool isDark;
  final String studentId;
  final String shortCode;
  final String department;
  final String currentSemester;
  final String currentSessionSemesterId;

  @override
  Widget build(BuildContext context) {
    final baseBorderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);
    final normalizedSemester = formatSemesterTitle(currentSemester);
    final fallbackSemester = formatSemesterFromSessionId(
      currentSessionSemesterId,
    );
    final displaySemester = normalizedSemester.isNotEmpty
        ? normalizedSemester
        : (fallbackSemester.isNotEmpty ? fallbackSemester : '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: BracuPalette.card(context),
        border: Border.all(color: baseBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headerTitle(
                    shortCode: shortCode,
                    studentId: studentId,
                    semester: displaySemester,
                  ),
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  department.isEmpty ? '' : department,
                  overflow: TextOverflow.fade,
                  softWrap: true,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _headerTitle({
    required String shortCode,
    required String studentId,
    required String semester,
  }) {
    final left = shortCode.isNotEmpty
        ? shortCode
        : (studentId.isEmpty ? '' : studentId);
    final right = semester.isEmpty ? '' : semester;
    return '${left.toUpperCase()} ${right.toUpperCase()}'.trim();
  }
}

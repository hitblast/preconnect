import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({
    super.key,
    required this.title,
    required this.targetDateTime,
  });

  final String title;
  final DateTime targetDateTime;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(minutes: 1), (tick) => tick),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final remaining = targetDateTime.difference(now);
        final dateTimeLabel = _formatSubtitle(targetDateTime, now);
        return BracuCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateTimeLabel,
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _ExamCountdownDigital(remaining: remaining),
            ],
          ),
        );
      },
    );
  }

  String _formatSubtitle(DateTime target, DateTime now) {
    return formatDateTimeLabel(target);
  }
}

class _ExamCountdownDigital extends StatelessWidget {
  const _ExamCountdownDigital({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final totalMinutes = remaining.inMinutes;
    final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
    final days = safeMinutes ~/ 1440;
    final hours = (safeMinutes ~/ 60) % 24;
    final minutes = safeMinutes % 60;

    Widget cell(String value, String label) {
      return SizedBox(
        width: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    final units = <({String value, String label})>[
      (value: days.toString(), label: 'Days'),
      (value: hours.toString().padLeft(2, '0'), label: 'Hours'),
      (value: minutes.toString().padLeft(2, '0'), label: 'Minutes'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          cell(units[i].value, units[i].label),
          if (i != units.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

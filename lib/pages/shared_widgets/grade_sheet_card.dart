import 'package:flutter/material.dart';
import 'package:preconnect/pages/grade_sheet_viewer.dart';
import 'package:preconnect/pages/ui_kit.dart';

const kGradeSheetTitle = 'Grade Sheet';
const kGradeSheetCardSubtitle = 'Latest Grade Sheet inside the app';
const kGradeSheetViewerSubtitle = 'PDF Document';

class GradeSheetCard extends StatelessWidget {
  const GradeSheetCard({
    super.key,
    this.title = kGradeSheetTitle,
    this.subtitle = kGradeSheetCardSubtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GradeSheetViewerPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: BracuPalette.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

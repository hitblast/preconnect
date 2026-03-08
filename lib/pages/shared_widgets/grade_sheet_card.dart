import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:native_file_preview/native_file_preview.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/web_pdf_opener.dart';

const kGradeSheetTitle = 'Grade Sheet';
const kGradeSheetCardSubtitle = 'Open your latest grade sheet PDF';

class GradeSheetCard extends StatefulWidget {
  const GradeSheetCard({
    super.key,
    this.title = kGradeSheetTitle,
    this.subtitle = kGradeSheetCardSubtitle,
  });

  final String title;
  final String subtitle;

  @override
  State<GradeSheetCard> createState() => _GradeSheetCardState();
}

class _GradeSheetCardState extends State<GradeSheetCard> {
  final NativeFilePreview _nativeFilePreview = NativeFilePreview();
  bool _isOpening = false;

  Future<void> _openGradeSheet() async {
    if (_isOpening) return;
    setState(() {
      _isOpening = true;
    });
    try {
      if (kIsWeb) {
        final bytes = await GradeSheetService().fetchGradeSheetBytes(
          fromGet: true,
        );
        if (!mounted) return;
        if (bytes == null || bytes.isEmpty) {
          showAppSnackBar(context, 'Could not fetch the latest grade sheet');
          return;
        }
        final fileName = await GradeSheetService().gradeSheetFileName();
        await openPdfInBrowser(bytes: bytes, fileName: '$fileName.pdf');
        return;
      }
      final gradeSheet = await GradeSheetService().fetchGradeSheet(
        fromGet: true,
      );
      if (!mounted) return;
      if (gradeSheet == null) {
        showAppSnackBar(context, 'Could not fetch the latest grade sheet');
        return;
      }
      await _nativeFilePreview.previewFile(gradeSheet.file.path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'NO_APP_FOUND' => 'No app found to open this PDF.',
        'FILE_NOT_FOUND' => 'The PDF file was not found.',
        _ => error.message ?? 'Could not open the PDF.',
      };
      showAppSnackBar(context, message);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not open the PDF.');
    } finally {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

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
                    widget.title,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
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
              onPressed: _isOpening ? null : _openGradeSheet,
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
              icon: _isOpening
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(_isOpening ? 'Opening' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }
}

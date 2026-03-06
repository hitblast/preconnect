import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/pages/shared_widgets/grade_sheet_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:share_plus/share_plus.dart';

class GradeSheetViewerPage extends StatefulWidget {
  const GradeSheetViewerPage({super.key});

  @override
  State<GradeSheetViewerPage> createState() => _GradeSheetViewerPageState();
}

class _GradeSheetViewerPageState extends State<GradeSheetViewerPage> {
  late final Stream<GradeSheetFile?> _stream;
  bool _isRefreshing = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _stream = GradeSheetService().watchGradeSheet();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      await GradeSheetService().fetchGradeSheet();
      if (!mounted) return;
      showAppSnackBar(context, 'Grade sheet refreshed');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _share(GradeSheetFile gradeSheet) async {
    if (_isSharing) return;
    setState(() {
      _isSharing = true;
    });
    try {
      final fileName = await GradeSheetService().gradeSheetFileName();
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(gradeSheet.file.path, name: '$fileName.pdf')],
          text: kGradeSheetTitle,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not share the file');
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BracuPageScaffold(
      title: kGradeSheetTitle,
      subtitle: kGradeSheetViewerSubtitle,
      icon: Icons.picture_as_pdf_outlined,
      body: StreamBuilder<GradeSheetFile?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuLoading(),
            );
          }

          final gradeSheet = snapshot.data;
          final file = gradeSheet?.file;
          if (file == null || gradeSheet == null) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuEmptyState(
                message: 'No grade sheet available.',
              ),
            );
          }

          return Stack(
            children: [
              PDFView(
                key: ValueKey<String>(file.path),
                filePath: file.path,
                fitPolicy: FitPolicy.BOTH,
                pageFling: false,
                pageSnap: false,
                nightMode: isDark,
                backgroundColor: isDark
                    ? const Color(0xFF05070B)
                    : const Color(0xFFF6FAFF),
                enableRenderDuringScale: true,
                useBestQuality: true,
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'grade-sheet-share',
                        onPressed: () => _share(gradeSheet),
                        backgroundColor: BracuPalette.primary,
                        foregroundColor: Colors.white,
                        child: _isSharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.share_outlined),
                      ),
                      const SizedBox(height: 10),
                      FloatingActionButton.small(
                        heroTag: 'grade-sheet-refresh',
                        onPressed: _refresh,
                        backgroundColor: BracuPalette.primary,
                        foregroundColor: Colors.white,
                        child: _isRefreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

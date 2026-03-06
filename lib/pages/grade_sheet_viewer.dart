import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/pages/shared_widgets/grade_sheet_card.dart';
import 'package:preconnect/pages/ui_kit.dart';

class GradeSheetViewerPage extends StatefulWidget {
  const GradeSheetViewerPage({super.key});

  @override
  State<GradeSheetViewerPage> createState() => _GradeSheetViewerPageState();
}

class _GradeSheetViewerPageState extends State<GradeSheetViewerPage> {
  late Future<GradeSheetFile?> _future;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _future = GradeSheetService().getGradeSheet();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      final next = await GradeSheetService().fetchGradeSheet();
      if (!mounted) return;
      setState(() {
        _future = Future<GradeSheetFile?>.value(next);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: kGradeSheetTitle,
      subtitle: kGradeSheetViewerSubtitle,
      icon: Icons.picture_as_pdf_outlined,
      body: FutureBuilder<GradeSheetFile?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuLoading(),
            );
          }

          final file = snapshot.data?.file;
          if (file == null) {
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
              PdfViewer.file(file.path, params: const PdfViewerParams()),
              Positioned(
                right: 16,
                bottom: 16,
                child: SafeArea(
                  child: FloatingActionButton.small(
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

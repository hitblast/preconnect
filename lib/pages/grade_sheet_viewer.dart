import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/pages/shared_widgets/grade_sheet_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class GradeSheetViewerPage extends StatefulWidget {
  const GradeSheetViewerPage({super.key});

  @override
  State<GradeSheetViewerPage> createState() => _GradeSheetViewerPageState();
}

class _GradeSheetViewerPageState extends State<GradeSheetViewerPage> {
  late final Stream<GradeSheetFile?> _stream;
  bool _isOpening = false;
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

  Future<void> _openExternally(GradeSheetFile gradeSheet) async {
    if (_isOpening) return;
    setState(() {
      _isOpening = true;
    });
    try {
      final opened = await launchUrl(
        gradeSheet.file.uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        showAppSnackBar(context, 'Could not open the file externally');
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not open the file externally');
    } finally {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

  String _fileSizeLabel(File file) {
    final bytes = file.lengthSync();
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  @override
  Widget build(BuildContext context) {
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              BracuCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your grade sheet is ready',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'PreConnect now keeps the PDF locally and opens it with any installed PDF app.',
                        style: TextStyle(
                          color: BracuPalette.textSecondary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.insert_drive_file_outlined,
                        label: 'File',
                        value: file.uri.pathSegments.isEmpty
                            ? 'Grade Sheet PDF'
                            : file.uri.pathSegments.last,
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.storage_outlined,
                        label: 'Size',
                        value: _fileSizeLabel(file),
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.offline_pin_outlined,
                        label: 'Source',
                        value: gradeSheet.fromCache
                            ? 'Cached'
                            : 'Fresh',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _openExternally(gradeSheet),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BracuPalette.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isOpening
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
                    : const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Externally'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _share(gradeSheet),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: BracuPalette.primary),
                  foregroundColor: BracuPalette.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isSharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined),
                label: const Text('Share PDF'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _refresh,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: BracuPalette.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

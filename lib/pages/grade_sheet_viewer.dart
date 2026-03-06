import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/pages/shared_widgets/grade_sheet_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GradeSheetViewerPage extends StatefulWidget {
  const GradeSheetViewerPage({super.key});

  @override
  State<GradeSheetViewerPage> createState() => _GradeSheetViewerPageState();
}

class _GradeSheetViewerPageState extends State<GradeSheetViewerPage> {
  static const String _viewerAssetPath = 'assets/pdf_viewer/index.html';
  static const int _base64ChunkLength = 50000;

  late final Stream<GradeSheetFile?> _stream;
  WebViewController? _webViewController;
  String? _viewerStatus;
  String? _lastRenderedPath;
  bool _isRefreshing = false;
  bool _isSharing = false;
  bool _isViewerLoading = true;
  bool _viewerReady = false;
  bool _renderInProgress = false;

  @override
  void initState() {
    super.initState();
    _stream = GradeSheetService().watchGradeSheet();
    if (!kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..addJavaScriptChannel(
          'PdfViewerChannel',
          onMessageReceived: _onViewerMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() {
                _viewerReady = true;
              });
            },
          ),
        )
        ..loadFlutterAsset(_viewerAssetPath);
    }
  }

  void _onViewerMessage(JavaScriptMessage message) {
    final payload = message.message.trim();
    if (!mounted) return;
    if (payload == 'ready') {
      setState(() {
        _viewerReady = true;
      });
      return;
    }
    if (payload == 'rendered') {
      setState(() {
        _isViewerLoading = false;
        _viewerStatus = null;
      });
      return;
    }
    if (payload.startsWith('error:')) {
      setState(() {
        _isViewerLoading = false;
        _viewerStatus = payload.substring(6).trim();
      });
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _isViewerLoading = true;
      _viewerStatus = null;
      _lastRenderedPath = null;
    });
    try {
      await GradeSheetService().fetchGradeSheet();
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

  Future<void> _renderPdf(File file) async {
    final controller = _webViewController;
    if (controller == null || !_viewerReady || _renderInProgress) return;
    final path = file.path;
    if (_lastRenderedPath == path) return;

    _renderInProgress = true;
    if (mounted) {
      setState(() {
        _isViewerLoading = true;
        _viewerStatus = null;
      });
    }

    try {
      final bytes = await file.readAsBytes();
      final base64Payload = base64Encode(bytes);
      final fileName = file.uri.pathSegments.isEmpty
          ? 'Grade sheet'
          : file.uri.pathSegments.last;
      await controller.runJavaScript(
        'window.startPdfTransfer(${jsonEncode(fileName)});',
      );
      for (
        var start = 0;
        start < base64Payload.length;
        start += _base64ChunkLength
      ) {
        final end = (start + _base64ChunkLength < base64Payload.length)
            ? start + _base64ChunkLength
            : base64Payload.length;
        final chunk = base64Payload.substring(start, end);
        await controller.runJavaScript(
          'window.appendPdfChunk(${jsonEncode(chunk)});',
        );
      }
      await controller.runJavaScript('window.finishPdfTransfer();');
      if (!mounted) return;
      setState(() {
        _lastRenderedPath = path;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _viewerStatus = error.toString();
        _isViewerLoading = false;
      });
    } finally {
      _renderInProgress = false;
    }
  }

  void _scheduleRender(File file) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_renderPdf(file));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
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

          if (!kIsWeb) {
            _scheduleRender(file);
          }

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: kIsWeb
                            ? const BracuEmptyState(
                                message:
                                    'WebView PDF rendering is available on mobile builds.',
                              )
                            : WebViewWidget(
                                key: ValueKey<String>(file.path),
                                controller: _webViewController!,
                              ),
                      ),
                      if (_isViewerLoading)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).scaffoldBackgroundColor.withValues(alpha: 0.92),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const BracuLoading(),
                                const SizedBox(height: 12),
                                Text(
                                  'Rendering PDF...',
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_viewerStatus != null && _viewerStatus!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      _viewerStatus!,
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _share(gradeSheet),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: BracuPalette.primary,
                            side: BorderSide(color: BracuPalette.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _isSharing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _refresh,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: BracuPalette.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _isRefreshing
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
                          label: const Text('Refresh'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

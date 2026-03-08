import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/platform_permissions.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/web_login_broker_service.dart';
import 'package:preconnect/tools/web_login_models.dart';

class WebLoginSetupPage extends StatefulWidget {
  const WebLoginSetupPage({super.key});

  @override
  State<WebLoginSetupPage> createState() => _WebLoginSetupPageState();
}

class _WebLoginSetupPageState extends State<WebLoginSetupPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );
  final WebLoginBrokerService _broker = WebLoginBrokerService();
  bool? _cameraGranted;
  bool _busy = false;
  String? _status;
  bool _loadingSessions = false;
  String? _sessionsError;
  List<WebActiveSession> _activeSessions = const <WebActiveSession>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensurePermission();
    _loadActiveSessions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _cameraGranted == true &&
        !_busy) {
      _controller.start().catchError((_) {});
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.stop();
    }
  }

  Future<void> _ensurePermission() async {
    final granted = await PlatformPermissions.requestScannerCameraPermission();
    if (!mounted) return;
    setState(() => _cameraGranted = granted);
    if (granted) {
      await _controller.start().catchError((_) {});
    }
  }

  Future<void> _refreshAll() async {
    await _ensurePermission();
    await _loadActiveSessions();
  }

  Future<void> _loadActiveSessions() async {
    if (!mounted) return;
    setState(() {
      _loadingSessions = true;
      _sessionsError = null;
    });
    try {
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Please sign in on this phone first.');
      }
      final sessions = await _broker.listActiveSessions(accessToken: accessToken);
      if (!mounted) return;
      setState(() {
        _activeSessions = sessions;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionsError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingSessions = false;
        });
      }
    }
  }

  Future<void> _revokeSession(WebActiveSession session) async {
    if (_loadingSessions) return;
    try {
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Please sign in on this phone first.');
      }
      await _broker.revokeSession(
        accessToken: accessToken,
        webSessionId: session.webSessionId,
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Web session logged out');
      await _loadActiveSessions();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _revokeAllSessions() async {
    if (_loadingSessions) return;
    try {
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Please sign in on this phone first.');
      }
      await _broker.revokeAllSessions(accessToken: accessToken);
      if (!mounted) return;
      showAppSnackBar(context, 'Logged out all web sessions');
      await _loadActiveSessions();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  String _formatTime(int millis) {
    if (millis <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _sessionLabel(WebActiveSession session) {
    final ua = session.userAgent.toLowerCase();
    if (ua.contains('safari') && !ua.contains('chrome')) return 'Safari';
    if (ua.contains('chrome')) return 'Chrome';
    if (ua.contains('firefox')) return 'Firefox';
    if (ua.contains('edg')) return 'Edge';
    return 'Browser session';
  }

  Future<void> _approve(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    await _controller.stop();
    try {
      final request = WebLoginRequestPayload.fromQrData(raw);
      if (request.type != 'web_login_request' || request.isExpired) {
        throw Exception('This browser QR is expired.');
      }
      final profile = await ProfileService().getProfile();
      final profileEmail = (profile?['studentEmail'] ?? profile?['email'] ?? '')
          .trim()
          .toLowerCase();
      final qrSessionEmail = request.studentEmail.trim().toLowerCase();
      final approvalEmail = profileEmail.contains('@')
          ? profileEmail
          : (qrSessionEmail.contains('@') ? qrSessionEmail : 'web@preconnect.app');
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      final refreshToken =
          (await TokenStorage.instance.read(key: 'refresh_token'))?.trim() ??
          '';
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        throw Exception('Mobile login is required before approving web login.');
      }
      await _broker.approve(
        request: request,
        payload: WebLoginApprovePayload(
          studentEmail: approvalEmail,
          studentId: (profile?['studentId'] ?? '').trim(),
          accessToken: accessToken,
          refreshToken: refreshToken,
          sessionExpiresAtMillis: DateTime.utc(2100, 1, 1).millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        _status = 'Web login approved for $approvalEmail';
      });
      showAppSnackBar(context, 'Web login approved');
      await _loadActiveSessions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString().replaceFirst('Exception: ', '');
      });
      showAppSnackBar(context, _status ?? 'Unable to approve web login');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_cameraGranted == true) {
          await _controller.start().catchError((_) {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Login to Web',
      subtitle: 'Scan browser QR',
      icon: Icons.qr_code_scanner_rounded,
      body: BracuRefreshList(
        onRefresh: _refreshAll,
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open PreConnect Web, then scan the browser QR here.',
                  style: TextStyle(color: BracuPalette.textSecondary(context)),
                ),
                const SizedBox(height: 12),
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _cameraGranted == true
                        ? MobileScanner(
                            controller: _controller,
                            onDetect: (capture) {
                              if (capture.barcodes.isEmpty) return;
                              final raw =
                                  capture.barcodes.first.rawValue?.trim() ?? '';
                              if (raw.isNotEmpty) {
                                _approve(raw);
                              }
                            },
                          )
                        : Center(
                            child: Text(
                              _cameraGranted == false
                                  ? 'Camera permission is required.'
                                  : 'Preparing camera...',
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Active Web Sessions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loadingSessions ? null : _loadActiveSessions,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                if (_loadingSessions) const LinearProgressIndicator(minHeight: 2),
                if (_sessionsError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _sessionsError!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ] else if (!_loadingSessions && _activeSessions.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No active browser sessions.',
                    style: TextStyle(color: BracuPalette.textSecondary(context)),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  for (final session in _activeSessions) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: BracuPalette.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _sessionLabel(session),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: BracuPalette.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Last seen: ${_formatTime(session.lastSeenAtMillis)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BracuPalette.textSecondary(context),
                                  ),
                                ),
                                Text(
                                  session.revoked
                                      ? 'Logged out'
                                      : 'Active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: session.revoked
                                        ? Colors.redAccent
                                        : BracuPalette.textSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: session.revoked
                                ? null
                                : () => _revokeSession(session),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _activeSessions.isEmpty || _loadingSessions
                          ? null
                          : _revokeAllSessions,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout All Web Sessions'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: Row(
              children: [
                Icon(
                  _busy
                      ? Icons.hourglass_top_rounded
                      : Icons.verified_user_outlined,
                  color: BracuPalette.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _status ??
                        (_busy
                            ? 'Approving browser login...'
                            : 'Scan the browser QR and approve login.'),
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => openExternalUrl(
              context,
              'https://web.preconnect.app',
              failureMessage: 'Unable to open web.preconnect.app',
            ),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: BracuPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.open_in_new,
                        color: BracuPalette.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open PreConnect Web',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PreConnect.app • Prepare. Connect. Succeed.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

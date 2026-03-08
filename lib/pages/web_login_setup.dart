import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_lock_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensurePermission();
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
      final studentEmail = (profile?['studentEmail'] ?? profile?['email'] ?? '')
          .trim()
          .toLowerCase();
      if (studentEmail.isEmpty) {
        throw Exception('Student email is not available on this device.');
      }
      final accountEmail = request.accountEmail.trim().toLowerCase();
      if (studentEmail != accountEmail) {
        throw Exception(
          'email does not match your student email.\n\nBrowser: ${request.accountEmail}\nApp: $studentEmail',
        );
      }
      final approved = await AppLockService().authenticate(
        reason: 'Approve login to web',
      );
      if (!approved) {
        throw Exception('Approval cancelled.');
      }
      final accessToken =
          (await TokenStorage.instance.read(key: 'access_token'))?.trim() ?? '';
      final refreshToken =
          (await TokenStorage.instance.read(key: 'refresh_token'))?.trim() ?? '';
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        throw Exception('Mobile login is required before approving web login.');
      }
      await _broker.approve(
        request: request,
        payload: WebLoginApprovePayload(
          studentEmail: studentEmail,
          studentId: (profile?['studentId'] ?? '').trim(),
          accessToken: accessToken,
          refreshToken: refreshToken,
          sessionExpiresAtMillis: DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        _status = 'Web login approved for ${request.accountEmail}';
      });
      showAppSnackBar(context, 'Web login approved');
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
        onRefresh: _ensurePermission,
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open PreConnect in Chrome, enter your student email there, then scan the browser QR here.',
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
                            ? 'Checking the email match and approving login...'
                            : 'Approval only succeeds if the browser email matches your student email.'),
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

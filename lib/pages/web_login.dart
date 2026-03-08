import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/web_login_broker_service.dart';
import 'package:preconnect/tools/web_login_models.dart';
import 'package:preconnect/tools/web_login_session_store.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  final WebLoginBrokerService _broker = WebLoginBrokerService();
  static WebLoginRequestPayload? _cachedRequest;
  static String? _cachedRequestQrData;
  bool _initializing = true;
  bool _signingIn = false;
  WebLoginRequestPayload? _request;
  String? _requestQrData;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  bool get _hasActiveQr =>
      _request != null &&
      _secondsLeft > 0 &&
      !(_request?.isExpired ?? true);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _resetToInitial() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _cachedRequest = null;
    _cachedRequestQrData = null;
    if (!mounted) return;
    setState(() {
      _request = null;
      _requestQrData = null;
      _secondsLeft = 0;
    });
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    final cachedRequest = _cachedRequest;
    final cachedQrData = _cachedRequestQrData;
    setState(() {
      _initializing = false;
      if (cachedRequest != null && !cachedRequest.isExpired) {
        _request = cachedRequest;
        _requestQrData = cachedQrData ?? cachedRequest.toQrData();
      }
    });
    final request = _request;
    if (request != null && !request.isExpired) {
      _startPolling(request);
    }
  }

  Future<void> _startLogin() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
    });
    try {
      final cachedRequest = _cachedRequest;
      final shouldReuse = cachedRequest != null && !cachedRequest.isExpired;
      final request = shouldReuse
          ? cachedRequest
          : (await _broker.createSession()).request;
      final qrData = shouldReuse && (_cachedRequestQrData ?? '').isNotEmpty
          ? _cachedRequestQrData!
          : request.toQrData();
      _cachedRequest = request;
      _cachedRequestQrData = qrData;
      _startPolling(request);
      if (!mounted) return;
      setState(() {
        _request = request;
        _requestQrData = qrData;
      });
    } catch (e) {
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
        });
      }
    }
  }

  void _startPolling(WebLoginRequestPayload request) {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    void updateCountdown() {
      final left =
          ((request.expiresAtMillis - DateTime.now().millisecondsSinceEpoch) /
                  1000)
              .ceil();
      if (left <= 0) {
        _resetToInitial();
        return;
      }
      if (!mounted) return;
      setState(() => _secondsLeft = left);
    }

    updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateCountdown();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_request == null) return;
      try {
        final status = await _broker.getStatus(_request!);
        if (status.expired) {
          _resetToInitial();
          return;
        }
        if (!status.approved) return;
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        final payload = await _broker.consume(_request!);
        await WebLoginSessionStore.save(
          accessToken: payload.accessToken,
          refreshToken: payload.refreshToken,
          sessionExpiresAtMillis: payload.sessionExpiresAtMillis,
          studentEmail: payload.studentEmail,
        );
        _cachedRequest = null;
        _cachedRequestQrData = null;
        RefreshBus.instance.notify(reason: 'auth');
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Login to Web',
      subtitle: 'Scan with your phone',
      icon: Icons.language_rounded,
      showBack: false,
      body: BracuRefreshList(
        onRefresh: _initialize,
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Tap Generate QR Code.\n2. Open PreConnect Settings on your phone.\n3. Login to Web and scan this QR code.',
                  textAlign: TextAlign.start,
                  style: TextStyle(color: BracuPalette.textSecondary(context)),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _initializing || _signingIn || _hasActiveQr
                        ? null
                        : _startLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(
                      _signingIn
                          ? 'Generating...'
                          : (_hasActiveQr
                                ? 'QR Active'
                                : 'Generate QR Code'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_request != null) ...[
            const SizedBox(height: 12),
            BracuCard(
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: BarcodeWidget(
                        barcode: Barcode.qrCode(),
                        data: _requestQrData ?? _request!.toQrData(),
                        color: Colors.black,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for phone approval. QR expires in ${_secondsLeft}s',
                    style: TextStyle(color: BracuPalette.textSecondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

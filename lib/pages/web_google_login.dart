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
  static String? _cachedError;
  bool _initializing = true;
  bool _signingIn = false;
  String? _error;
  WebLoginRequestPayload? _request;
  String? _requestQrData;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  String _toUserMessage(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    final normalized = raw.toLowerCase();

    if (normalized.contains('qr expired')) {
      return 'This QR code has expired. Sign in again to get a new one.';
    }
    if (normalized.contains('session expired') ||
        normalized.contains('expired')) {
      return 'This login session expired. Please generate a new QR code and try again.';
    }
    if (normalized.contains('network') || normalized.contains('socket')) {
      return 'Something went wrong while contacting the server. Please try again.';
    }

    return 'Something went wrong. Please try again.';
  }

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

  Future<void> _initialize() async {
    if (!mounted) return;
    final cachedRequest = _cachedRequest;
    final cachedQrData = _cachedRequestQrData;
    setState(() {
      _initializing = false;
      _error = _cachedError;
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
      _error = null;
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
      _cachedError = null;
      _startPolling(request);
      if (!mounted) return;
      setState(() {
        _request = request;
        _requestQrData = qrData;
      });
    } catch (e) {
      if (!mounted) return;
      _cachedError = _toUserMessage(e);
      setState(() {
        _error = _cachedError;
      });
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
      if (!mounted) return;
      setState(() => _secondsLeft = left < 0 ? 0 : left);
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
          _pollTimer?.cancel();
          _countdownTimer?.cancel();
          _cachedRequest = null;
          _cachedRequestQrData = null;
          _cachedError =
              'This QR code has expired. Start again to generate a new one.';
          if (!mounted) return;
          setState(() {
            _error = _cachedError;
            _request = null;
            _requestQrData = null;
          });
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
          accountEmail: payload.studentEmail,
        );
        _cachedRequest = null;
        _cachedRequestQrData = null;
        _cachedError = null;
        RefreshBus.instance.notify(reason: 'auth');
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      } catch (e) {
        final message = _toUserMessage(e);
        if (!mounted) return;
        setState(() {
          _error = message;
        });
      }
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
                  '1. Tap Generate QR Code.\n2. Open PreConnect on your phone.\n3. Go to Settings > Login to Web and scan this QR code.',
                  textAlign: TextAlign.start,
                  style: TextStyle(color: BracuPalette.textSecondary(context)),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _initializing || _signingIn ? null : _startLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(
                      _signingIn ? 'Generating...' : 'Generate QR Code',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: _request == null
                ? Text(
                    _initializing
                        ? 'Preparing login...'
                        : 'Generate a QR code to start browser login.',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  )
                : Column(
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
                        _secondsLeft > 0
                            ? 'Waiting for phone approval. QR expires in ${_secondsLeft}s'
                            : 'QR expired',
                        style: TextStyle(
                          color: _secondsLeft > 0
                              ? BracuPalette.textSecondary(context)
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
          ),
          if ((_error ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            BracuCard(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

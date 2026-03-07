import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/firebase_bootstrap.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/web_login_broker_service.dart';
import 'package:preconnect/tools/web_login_models.dart';
import 'package:preconnect/tools/web_login_session_store.dart';

class WebGoogleLoginPage extends StatefulWidget {
  const WebGoogleLoginPage({super.key});

  @override
  State<WebGoogleLoginPage> createState() => _WebGoogleLoginPageState();
}

class _WebGoogleLoginPageState extends State<WebGoogleLoginPage> {
  final WebLoginBrokerService _broker = WebLoginBrokerService();
  static String? _cachedGoogleEmail;
  static WebLoginRequestPayload? _cachedRequest;
  static String? _cachedError;
  bool _initializing = true;
  bool _signingIn = false;
  String? _error;
  String? _googleEmail;
  WebLoginRequestPayload? _request;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

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
    await FirebaseBootstrap.initializeIfNeeded();
    if (!mounted) return;
    final cachedRequest = _cachedRequest;
    final cachedEmail = _cachedGoogleEmail;
    setState(() {
      _initializing = false;
      if (!FirebaseBootstrap.isAvailable) {
        _error =
            'Firebase web auth is not configured. Run flutterfire configure and update firebase_options.dart.';
      } else {
        _error = _cachedError;
        _googleEmail = cachedEmail;
        if (cachedRequest != null && !cachedRequest.isExpired) {
          _request = cachedRequest;
        }
      }
    });
    final request = _request;
    if (request != null && !request.isExpired) {
      _startPolling(request);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final credential = await FirebaseAuth.instance.signInWithPopup(provider);
      final email = (credential.user?.email ?? '').trim();
      if (email.isEmpty) {
        throw Exception('Google did not return an email address.');
      }
      final cachedRequest = _cachedRequest;
      final normalizedEmail = email.toLowerCase();
      final shouldReuse =
          cachedRequest != null &&
          !cachedRequest.isExpired &&
          (_cachedGoogleEmail ?? '').toLowerCase() == normalizedEmail;
      final request =
          shouldReuse
              ? cachedRequest
              : (await _broker.createSession(googleEmail: email)).request;
      _cachedGoogleEmail = email;
      _cachedRequest = request;
      _cachedError = null;
      _startPolling(request);
      if (!mounted) return;
      setState(() {
        _googleEmail = email;
        _request = request;
      });
    } catch (e) {
      if (!mounted) return;
      _cachedError = e.toString().replaceFirst('Exception: ', '');
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
          _cachedError = 'QR expired. Sign in with Google again to refresh it.';
          if (!mounted) return;
          setState(() {
            _error = _cachedError;
            _request = null;
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
          googleEmail: _googleEmail ?? payload.studentEmail,
        );
        _cachedRequest = null;
        _cachedError = null;
        RefreshBus.instance.notify(reason: 'auth');
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } catch (e) {
        final message = e.toString().replaceFirst('Exception: ', '');
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
      title: 'Login with Google',
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
                  '1. Continue with Google using your student email.\n2. Open PreConnect on your phone.\n3. Go to Settings > Login to Web and scan the QR.',
                  style: TextStyle(color: BracuPalette.textSecondary(context)),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _initializing || !FirebaseBootstrap.isAvailable || _signingIn
                            ? null
                            : _signInWithGoogle,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(
                      _signingIn
                          ? 'Connecting Google...'
                          : 'Continue with Google',
                    ),
                  ),
                ),
                if ((_googleEmail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Google account: $_googleEmail',
                    style: TextStyle(color: BracuPalette.textPrimary(context)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: _request == null
                ? Text(
                    _initializing
                        ? 'Preparing Google sign-in...'
                        : 'Sign in with Google to generate the browser QR.',
                    style: TextStyle(color: BracuPalette.textSecondary(context)),
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
                            data: _request!.toQrData(),
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

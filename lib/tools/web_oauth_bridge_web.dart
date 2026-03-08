// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'web_oauth_bridge.dart';

class _WebOAuthBridge implements WebOAuthBridge {
  @override
  Future<String> signInAndGetEmail() async {
    final origin = html.window.location.origin;
    final popup = html.window.open(
      '$origin/auth/google/start',
      'preconnect_google_oauth',
      'width=520,height=680,menubar=no,toolbar=no,location=yes,resizable=yes,scrollbars=yes,status=no',
    );
    final completer = Completer<String>();
    late StreamSubscription<html.MessageEvent> sub;
    late Timer timeout;
    late Timer popupWatch;

    void completeError(String message) {
      if (completer.isCompleted) return;
      completer.completeError(Exception(message));
    }

    sub = html.window.onMessage.listen((event) {
      if (event.origin != origin) return;
      dynamic data = event.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return;
        }
      }
      if (data is! Map) return;
      if (data['type'] != 'preconnect_google_oauth') return;
      final error = '${data['error'] ?? ''}'.trim();
      if (error.isNotEmpty) {
        completeError(error);
        return;
      }
      final email = '${data['email'] ?? ''}'.trim().toLowerCase();
      if (email.isEmpty) {
        completeError('Google sign-in did not return an email.');
        return;
      }
      if (!completer.isCompleted) {
        completer.complete(email);
      }
    });

    timeout = Timer(const Duration(minutes: 2), () {
      completeError('Sign-in timed out. Please try again.');
    });
    popupWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (completer.isCompleted) return;
      if (popup.closed == true) {
        completeError('Sign-in popup was closed before completion.');
      }
    });

    try {
      return await completer.future;
    } finally {
      timeout.cancel();
      popupWatch.cancel();
      await sub.cancel();
      try {
        popup.close();
      } catch (_) {}
    }
  }
}

WebOAuthBridge createOAuthBridgeImpl() => _WebOAuthBridge();

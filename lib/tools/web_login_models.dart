import 'dart:convert';

import 'package:archive/archive.dart';

class WebLoginRequestPayload {
  const WebLoginRequestPayload({
    required this.version,
    required this.type,
    required this.sessionId,
    required this.sessionToken,
    required this.studentEmail,
    required this.nonce,
    required this.expiresAtMillis,
  });

  final int version;
  final String type;
  final String sessionId;
  final String sessionToken;
  final String studentEmail;
  final String nonce;
  final int expiresAtMillis;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMillis;

  Map<String, dynamic> toJson() => {
    'v': version,
    't': type,
    'sid': sessionId,
    'st': sessionToken,
    'se': studentEmail,
    'n': nonce,
    'exp': expiresAtMillis,
  };

  String toQrData() {
    final raw = jsonEncode(toJson());
    final encoded = utf8.encode(raw);
    final gzip = GZipEncoder().encode(encoded);
    return base64Url.encode(gzip);
  }

  static WebLoginRequestPayload fromQrData(String data) {
    final bytes = base64Url.decode(base64Url.normalize(data.trim()));
    final jsonStr = utf8.decode(GZipDecoder().decodeBytes(bytes));
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return WebLoginRequestPayload(
      version: (json['v'] as num?)?.toInt() ?? 1,
      type: '${json['t'] ?? json['type'] ?? ''}',
      sessionId: '${json['sid'] ?? json['sessionId'] ?? ''}',
      sessionToken: '${json['st'] ?? json['sessionToken'] ?? ''}',
      studentEmail:
          '${json['se'] ?? json['studentEmail'] ?? json['googleEmail'] ?? json['accountEmail'] ?? ''}',
      nonce: '${json['n'] ?? json['nonce'] ?? ''}',
      expiresAtMillis:
          (json['exp'] as num?)?.toInt() ??
          (json['expiresAt'] as num?)?.toInt() ??
          0,
    );
  }
}

class WebLoginApprovePayload {
  const WebLoginApprovePayload({
    required this.studentEmail,
    required this.studentId,
    required this.accessToken,
    required this.refreshToken,
    required this.sessionExpiresAtMillis,
  });

  final String studentEmail;
  final String studentId;
  final String accessToken;
  final String refreshToken;
  final int sessionExpiresAtMillis;

  Map<String, dynamic> toJson() => {
    'studentEmail': studentEmail,
    'studentId': studentId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'sessionExpiresAt': sessionExpiresAtMillis,
  };

  static WebLoginApprovePayload fromJson(Map<String, dynamic> json) {
    return WebLoginApprovePayload(
      studentEmail: '${json['studentEmail'] ?? ''}',
      studentId: '${json['studentId'] ?? ''}',
      accessToken: '${json['accessToken'] ?? ''}',
      refreshToken: '${json['refreshToken'] ?? ''}',
      sessionExpiresAtMillis: (json['sessionExpiresAt'] as num?)?.toInt() ?? 0,
    );
  }
}

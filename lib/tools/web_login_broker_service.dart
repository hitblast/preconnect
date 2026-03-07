import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/web_login_models.dart';

class WebLoginBrokerSession {
  const WebLoginBrokerSession({
    required this.request,
    required this.status,
  });

  final WebLoginRequestPayload request;
  final String status;
}

class WebLoginBrokerStatus {
  const WebLoginBrokerStatus({
    required this.status,
    required this.sessionId,
    required this.approved,
    required this.expired,
  });

  final String status;
  final String sessionId;
  final bool approved;
  final bool expired;
}

class WebLoginBrokerService {
  static const Duration _timeout = Duration(seconds: 12);
  final http.Client _client;

  WebLoginBrokerService({http.Client? client}) : _client = client ?? http.Client();

  String get _base => ApiConfig.webLoginBrokerBase;

  Future<WebLoginBrokerSession> createSession({
    required String googleEmail,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/session'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'googleEmail': googleEmail}),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Unable to create login session');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WebLoginBrokerSession(
      request: WebLoginRequestPayload(
        version: 1,
        type: 'web_login_request',
        sessionId: '${json['sessionId'] ?? ''}',
        sessionToken: '${json['sessionToken'] ?? ''}',
        googleEmail: '${json['googleEmail'] ?? ''}',
        nonce: '${json['nonce'] ?? ''}',
        expiresAtMillis: (json['expiresAt'] as num?)?.toInt() ?? 0,
      ),
      status: '${json['status'] ?? 'pending'}',
    );
  }

  Future<WebLoginBrokerStatus> getStatus(WebLoginRequestPayload request) async {
    final uri = Uri.parse(
      '$_base/web-login/session/${request.sessionId}'
      '?sessionToken=${Uri.encodeQueryComponent(request.sessionToken)}',
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Unable to check login status');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WebLoginBrokerStatus(
      status: '${json['status'] ?? ''}',
      sessionId: '${json['sessionId'] ?? ''}',
      approved: json['approved'] == true,
      expired: json['expired'] == true,
    );
  }

  Future<WebLoginApprovePayload> consume(WebLoginRequestPayload request) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/session/${request.sessionId}/consume'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'sessionToken': request.sessionToken}),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Unable to complete web login');
    }
    return WebLoginApprovePayload.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> approve({
    required WebLoginRequestPayload request,
    required WebLoginApprovePayload payload,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/session/${request.sessionId}/approve'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sessionToken': request.sessionToken,
            'googleEmail': request.googleEmail,
            ...payload.toJson(),
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      final body = response.body.trim();
      throw Exception(body.isEmpty ? 'Unable to approve web login' : body);
    }
  }
}

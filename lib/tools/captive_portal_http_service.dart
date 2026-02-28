import 'dart:convert';
import 'dart:io';

import 'package:preconnect/tools/user_agent.dart';

class CaptivePortalHttpResult {
  const CaptivePortalHttpResult({
    required this.statusCode,
    required this.uri,
    required this.body,
    required this.location,
  });

  final int statusCode;
  final Uri uri;
  final String body;
  final Uri? location;
}

class CaptivePortalHttpService {
  CaptivePortalHttpService._();

  static final CaptivePortalHttpService instance = CaptivePortalHttpService._();
  static final Uri defaultProbeUri = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );

  static const Duration _connectionTimeout = Duration(seconds: 10);

  HttpClient newClient() {
    final client = HttpClient()..userAgent = kPreconnectUserAgent;
    client.connectionTimeout = _connectionTimeout;
    return client;
  }

  Future<void> requestSessionExtension(Uri uri) async {
    final client = newClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
    } finally {
      client.close(force: true);
    }
  }

  List<Uri> candidateProbeUris({Uri? portalUrl, Uri? fallbackProbeUri}) {
    final uris = <Uri>[];
    if (portalUrl != null) {
      uris.add(portalUrl);
    }
    uris.add(fallbackProbeUri ?? defaultProbeUri);
    final seen = <String>{};
    return [
      for (final uri in uris)
        if (seen.add(uri.toString())) uri,
    ];
  }

  Future<CaptivePortalHttpResult?> probeWithFallback({
    required HttpClient client,
    required Map<String, Cookie> cookies,
    Uri? portalUrl,
    Uri? fallbackProbeUri,
  }) async {
    for (final probeUri in candidateProbeUris(
      portalUrl: portalUrl,
      fallbackProbeUri: fallbackProbeUri,
    )) {
      try {
        final result = await getWithRedirects(
          client: client,
          uri: probeUri,
          cookies: cookies,
        );
        if (result.statusCode > 0) {
          return result;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<bool> isValidatedViaProbeFallback({
    required HttpClient client,
    required Map<String, Cookie> cookies,
    Uri? portalUrl,
    Uri? fallbackProbeUri,
  }) async {
    for (final probeUri in candidateProbeUris(
      portalUrl: portalUrl,
      fallbackProbeUri: fallbackProbeUri,
    )) {
      try {
        final result = await getWithRedirects(
          client: client,
          uri: probeUri,
          cookies: cookies,
        );
        if (result.statusCode == 204) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<CaptivePortalHttpResult> getWithRedirects({
    required HttpClient client,
    required Uri uri,
    required Map<String, Cookie> cookies,
  }) async {
    var current = uri;
    for (var i = 0; i < 8; i++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      final cookieHeader = _cookieHeader(cookies);
      if (cookieHeader != null) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      final response = await request.close();
      _captureCookies(response, cookies);

      final status = response.statusCode;
      final location = response.headers.value(HttpHeaders.locationHeader);
      final body = await response.transform(utf8.decoder).join();

      if (status >= 300 && status < 400 && location != null) {
        current = Uri.parse(location).isAbsolute
            ? Uri.parse(location)
            : current.resolve(location);
        continue;
      }

      return CaptivePortalHttpResult(
        statusCode: status,
        uri: current,
        body: body,
        location: location == null ? null : Uri.parse(location),
      );
    }
    return CaptivePortalHttpResult(
      statusCode: 0,
      uri: current,
      body: '',
      location: null,
    );
  }

  Future<CaptivePortalHttpResult> postOnce({
    required HttpClient client,
    required Uri uri,
    required String body,
    required Map<String, Cookie> cookies,
  }) async {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded',
    );
    final cookieHeader = _cookieHeader(cookies);
    if (cookieHeader != null) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    request.write(body);
    final response = await request.close();
    _captureCookies(response, cookies);
    final location = response.headers.value(HttpHeaders.locationHeader);
    final text = await response.transform(utf8.decoder).join();

    return CaptivePortalHttpResult(
      statusCode: response.statusCode,
      uri: uri,
      body: text,
      location: location == null ? null : Uri.parse(location),
    );
  }

  void _captureCookies(HttpClientResponse response, Map<String, Cookie> jar) {
    for (final cookie in response.cookies) {
      jar[cookie.name] = cookie;
    }
  }

  String? _cookieHeader(Map<String, Cookie> jar) {
    if (jar.isEmpty) return null;
    return jar.values.map((c) => '${c.name}=${c.value}').join('; ');
  }
}

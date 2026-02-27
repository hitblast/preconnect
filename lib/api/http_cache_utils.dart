import 'package:http/http.dart' as http;

Map<String, String> ifNoneMatchHeader(String? etag) {
  final value = (etag ?? '').trim();
  if (value.isEmpty) return const <String, String>{};
  return <String, String>{'If-None-Match': value};
}

String? extractEtagFromHeaders(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'etag') {
      final value = entry.value.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

String? extractEtagFromResponse(http.Response response) {
  return extractEtagFromHeaders(response.headers);
}

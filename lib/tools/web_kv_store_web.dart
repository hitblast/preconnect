// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

String? webKvGet(String key) {
  try {
    final local = html.window.localStorage[key];
    if (local != null && local.isNotEmpty) return local;
  } catch (_) {}
  try {
    final session = html.window.sessionStorage[key];
    if (session != null && session.isNotEmpty) return session;
  } catch (_) {}
  return null;
}

bool webKvSet(String key, String? value) {
  try {
    if (value == null) {
      html.window.localStorage.remove(key);
    } else {
      html.window.localStorage[key] = value;
    }
    return true;
  } catch (_) {}
  try {
    if (value == null) {
      html.window.sessionStorage.remove(key);
    } else {
      html.window.sessionStorage[key] = value;
    }
    return true;
  } catch (_) {}
  return false;
}

void webKvClearKeys(Iterable<String> keys) {
  for (final key in keys) {
    try {
      html.window.localStorage.remove(key);
    } catch (_) {}
    try {
      html.window.sessionStorage.remove(key);
    } catch (_) {}
  }
}

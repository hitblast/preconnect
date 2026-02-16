import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileImageCache {
  ProfileImageCache._();
  static final instance = ProfileImageCache._();

  static const _cachedUrlKey = 'profile_image_cached_url';
  static const _cachedBytesKey = 'profile_image_cached_bytes';

  File? _cachedFile;

  Future<File?> getProfileImage(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return null;

    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return _cachedFile;
    }

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/profile_photo.jpg');
    final prefs = await SharedPreferences.getInstance();

    final cachedUrl = prefs.getString(_cachedUrlKey);
    final cachedBytes = prefs.getString(_cachedBytesKey);
    if (cachedUrl == photoUrl &&
        cachedBytes != null &&
        cachedBytes.isNotEmpty &&
        !file.existsSync()) {
      try {
        await file.writeAsBytes(base64Decode(cachedBytes), flush: true);
      } catch (_) {}
    }

    if (file.existsSync() &&
        file.lengthSync() > 0 &&
        (cachedUrl == null || cachedUrl == photoUrl)) {
      _cachedFile = file;
      _downloadInBackground(photoUrl, file);
      return file;
    }

    try {
      final response = await http.get(Uri.parse(photoUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await prefs.setString(_cachedUrlKey, photoUrl);
        await prefs.setString(
          _cachedBytesKey,
          base64Encode(response.bodyBytes),
        );
        _cachedFile = file;
        return file;
      }
    } catch (_) {}

    return null;
  }

  void _downloadInBackground(String url, File file) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cachedUrlKey, url);
        await prefs.setString(
          _cachedBytesKey,
          base64Encode(response.bodyBytes),
        );
      }
    } catch (_) {}
  }

  void invalidate() {
    _cachedFile = null;
  }

  Future<void> clear() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/profile_photo.jpg');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUrlKey);
    await prefs.remove(_cachedBytesKey);
    _cachedFile = null;
  }
}

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:permission_handler/permission_handler.dart';

class PlatformPermissions {
  const PlatformPermissions._();

  static Future<bool> requestScannerCameraPermission() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.macOS) return true;

    final status = await Permission.camera.status;
    final requested = status.isGranted
        ? status
        : await Permission.camera.request();
    return requested.isGranted;
  }

  static Future<bool> requestGalleryImagePermission() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.macOS) return true;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final photos = await Permission.photos.request();
      if (photos.isGranted) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }

    return true;
  }
}

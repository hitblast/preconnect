import 'dart:typed_data';

import 'web_pdf_opener_stub.dart'
    if (dart.library.html) 'web_pdf_opener_web.dart';

Future<void> openPdfInBrowser({
  required Uint8List bytes,
  required String fileName,
}) => openPdfInBrowserImpl(bytes: bytes, fileName: fileName);

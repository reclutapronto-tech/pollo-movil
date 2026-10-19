import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Strips EXIF metadata (GPS coordinates, timestamps, device info) from photos
/// before upload to prevent unintended location and identity leaks.
///
/// The `image` package decode → encode cycle naturally drops EXIF because
/// `encodeJpg` does not write back EXIF from the decoded [Image] object.
/// This utility makes that behavior explicit and provides a clear API for
/// any upload path that doesn't already go through decode → encode (e.g.
/// draft uploads).
class ExifStripper {
  const ExifStripper();

  /// Strip EXIF from raw JPEG bytes. Returns clean JPEG bytes.
  ///
  /// If the image cannot be decoded, returns the original bytes unchanged
  /// rather than blocking the upload.
  Uint8List stripBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  }

  /// Strip EXIF from a file in-place.
  Future<void> stripFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final stripped = stripBytes(bytes);
    await file.writeAsBytes(stripped, flush: true);
  }
}

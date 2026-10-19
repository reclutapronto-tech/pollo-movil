import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class PhotoEnhancer {
  const PhotoEnhancer();

  Future<void> autoEnhanceFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final enhanced = autoEnhanceBytes(bytes);
    await file.writeAsBytes(enhanced, flush: true);
  }

  Uint8List autoEnhanceBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const PhotoEnhancerException('Photo could not be enhanced.');
    }

    final adjusted = img.adjustColor(
      decoded,
      brightness: 1.04,
      contrast: 1.08,
      saturation: 1.05,
    );
    final sharpened = img.convolution(
      adjusted,
      filter: const <num>[0, -1, 0, -1, 5, -1, 0, -1, 0],
    );

    return Uint8List.fromList(img.encodeJpg(sharpened, quality: 92));
  }
}

class PhotoEnhancerException implements Exception {
  const PhotoEnhancerException(this.message);

  final String message;

  @override
  String toString() => 'PhotoEnhancerException: $message';
}

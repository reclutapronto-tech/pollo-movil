import 'dart:typed_data';

import 'package:fieldops_mobile/features/camera/data/photo_enhancer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('auto enhance returns a valid non-empty jpeg payload', () {
    const enhancer = PhotoEnhancer();
    final image = img.Image(width: 8, height: 8);
    img.fill(image, color: img.ColorRgb8(96, 112, 128));
    final original = Uint8List.fromList(img.encodeJpg(image, quality: 88));

    final enhanced = enhancer.autoEnhanceBytes(original);

    expect(enhanced, isNotEmpty);
    expect(img.decodeImage(enhanced), isNotNull);
  });
}

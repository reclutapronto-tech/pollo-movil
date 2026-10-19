import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// Metadata burned onto proof photos as a tamper-evident overlay.
class ProofStampMetadata {
  const ProofStampMetadata({
    required this.workerEmail,
    required this.jobName,
    required this.capturedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });

  final String workerEmail;
  final String jobName;
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
}

/// Renders a proof stamp overlay (timestamp, GPS, worker, job) directly onto
/// photo bytes using the `image` package.
///
/// The stamp is a semi-transparent dark banner at the bottom of the image with
/// white text lines. This makes the metadata permanently part of the image
/// file — it cannot be removed after upload.
class ProofStampRenderer {
  const ProofStampRenderer();

  /// Stamp a file in-place. Returns the stamped file path (same path).
  Future<String> stampFile(String filePath, ProofStampMetadata metadata) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final stamped = stampBytes(bytes, metadata);
    await file.writeAsBytes(stamped, flush: true);
    return filePath;
  }

  /// Stamp raw JPEG bytes and return the stamped JPEG.
  Uint8List stampBytes(Uint8List bytes, ProofStampMetadata metadata) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ProofStampException('Could not decode image for stamping.');
    }

    final stamped = _applyStamp(decoded, metadata);
    return Uint8List.fromList(img.encodeJpg(stamped, quality: 92));
  }

  img.Image _applyStamp(img.Image image, ProofStampMetadata metadata) {
    final lines = _buildStampLines(metadata);
    final lineCount = lines.length;

    // Font metrics — using the built-in arial_14 bitmap font for reliability.
    final font = img.arial14;
    final lineHeight = font.lineHeight + 2;
    final bannerHeight = (lineCount * lineHeight) + 20; // 10px padding top+bottom

    // Semi-transparent dark banner at the bottom
    final bannerTop = image.height - bannerHeight;
    final bannerColor = img.ColorRgba8(0, 0, 0, 178); // ~70% opacity black

    img.fillRect(
      image,
      x1: 0,
      y1: bannerTop,
      x2: image.width,
      y2: image.height,
      color: bannerColor,
    );

    // Draw each text line
    final textColor = img.ColorRgba8(255, 255, 255, 240);
    for (var i = 0; i < lines.length; i++) {
      final y = bannerTop + 10 + (i * lineHeight);
      img.drawString(
        image,
        lines[i],
        font: font,
        x: 12,
        y: y,
        color: textColor,
      );
    }

    // FieldOps watermark on the right side of the first line
    img.drawString(
      image,
      'FieldOps',
      font: font,
      x: image.width - 80,
      y: bannerTop + 10,
      color: img.ColorRgba8(255, 255, 255, 128),
    );

    return image;
  }

  List<String> _buildStampLines(ProofStampMetadata metadata) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final timestamp = dateFormat.format(metadata.capturedAt.toLocal());

    final lines = <String>[
      timestamp,
      'Worker: ${metadata.workerEmail}',
      'Job: ${metadata.jobName}',
    ];

    if (metadata.latitude != null && metadata.longitude != null) {
      final lat = metadata.latitude!.toStringAsFixed(6);
      final lng = metadata.longitude!.toStringAsFixed(6);
      var gpsLine = 'GPS: $lat, $lng';
      if (metadata.accuracyMeters != null) {
        gpsLine += ' (+/- ${metadata.accuracyMeters!.toStringAsFixed(0)}m)';
      }
      lines.add(gpsLine);
    }

    return lines;
  }
}

class ProofStampException implements Exception {
  const ProofStampException(this.message);

  final String message;

  @override
  String toString() => 'ProofStampException: $message';
}

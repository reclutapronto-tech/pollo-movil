// Photo annotation model for drawing on proof photos.
// Annotations stored as SVG overlay, same pattern as proof stamp.

/// Types of annotations that can be drawn on photos.
enum AnnotationType { arrow, circle, rectangle, text, freehand }

class PhotoAnnotation {
  const PhotoAnnotation({
    required this.id,
    required this.type,
    required this.points,
    this.text,
    this.color = '#FF0000',
    this.strokeWidth = 3.0,
  });

  final String id;
  final AnnotationType type;
  final List<({double x, double y})> points;
  final String? text;
  final String color;
  final double strokeWidth;
}

class AnnotatedPhoto {
  const AnnotatedPhoto({
    required this.mediaAssetId,
    required this.annotations,
    required this.annotatedBy,
    required this.annotatedAt,
  });

  final String mediaAssetId;
  final List<PhotoAnnotation> annotations;
  final String annotatedBy;
  final DateTime annotatedAt;

  /// Generate SVG overlay from annotations.
  String toSvg({required int width, required int height}) {
    final buffer = StringBuffer();
    buffer.writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height">');

    for (final ann in annotations) {
      switch (ann.type) {
        case AnnotationType.circle:
          if (ann.points.length >= 2) {
            final cx = ann.points[0].x;
            final cy = ann.points[0].y;
            final rx = (ann.points[1].x - cx).abs();
            final ry = (ann.points[1].y - cy).abs();
            buffer.writeln(
              '<ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" '
              'stroke="${ann.color}" stroke-width="${ann.strokeWidth}" fill="none"/>',
            );
          }
        case AnnotationType.rectangle:
          if (ann.points.length >= 2) {
            final x = ann.points[0].x;
            final y = ann.points[0].y;
            final w = ann.points[1].x - x;
            final h = ann.points[1].y - y;
            buffer.writeln(
              '<rect x="$x" y="$y" width="$w" height="$h" '
              'stroke="${ann.color}" stroke-width="${ann.strokeWidth}" fill="none"/>',
            );
          }
        case AnnotationType.arrow:
          if (ann.points.length >= 2) {
            final x1 = ann.points[0].x;
            final y1 = ann.points[0].y;
            final x2 = ann.points[1].x;
            final y2 = ann.points[1].y;
            buffer.writeln(
              '<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" '
              'stroke="${ann.color}" stroke-width="${ann.strokeWidth}" marker-end="url(#arrowhead)"/>',
            );
          }
        case AnnotationType.text:
          if (ann.points.isNotEmpty && ann.text != null) {
            buffer.writeln(
              '<text x="${ann.points[0].x}" y="${ann.points[0].y}" '
              'fill="${ann.color}" font-size="16" font-family="system-ui">${ann.text}</text>',
            );
          }
        case AnnotationType.freehand:
          if (ann.points.length >= 2) {
            final d = ann.points
                .map((p) => '${p.x},${p.y}')
                .join(' L');
            buffer.writeln(
              '<polyline points="$d" '
              'stroke="${ann.color}" stroke-width="${ann.strokeWidth}" fill="none"/>',
            );
          }
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }
}

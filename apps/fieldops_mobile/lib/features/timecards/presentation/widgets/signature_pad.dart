import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A simple signature capture pad.
///
/// The user draws on a canvas. [onSigned] fires with the PNG bytes of
/// the drawn signature when "Done" is tapped.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.onSigned, this.onCancel});

  final void Function(Uint8List pngBytes) onSigned;
  final VoidCallback? onCancel;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  bool _hasDrawn = false;

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = [];
      _hasDrawn = false;
    });
  }

  Future<void> _export() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(600, 200);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    widget.onSigned(byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Draw your signature', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surfaceWhite,
            borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
            border: Border.all(color: palette.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
            child: GestureDetector(
              onPanStart: (d) {
                setState(() {
                  _current = [d.localPosition];
                  _hasDrawn = true;
                });
              },
              onPanUpdate: (d) {
                setState(() {
                  _current = [..._current, d.localPosition];
                });
              },
              onPanEnd: (_) {
                setState(() {
                  _strokes.add(_current);
                  _current = [];
                });
              },
              child: CustomPaint(
                painter: _SignaturePainter(
                  strokes: _strokes,
                  current: _current,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _hasDrawn ? _clear : null,
              child: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _hasDrawn ? _export : null,
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, required this.current});

  final List<List<Offset>> strokes;
  final List<Offset> current;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in [...strokes, current]) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}

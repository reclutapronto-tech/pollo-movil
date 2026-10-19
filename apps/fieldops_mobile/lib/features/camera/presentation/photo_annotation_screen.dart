import 'dart:io';
import 'dart:ui' as ui;

import 'package:fieldops_mobile/features/camera/domain/photo_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

/// Annotation editor — draw arrows, circles, rectangles, or freehand
/// strokes over a photo. Returns the path to the annotated PNG on confirm.
class PhotoAnnotationScreen extends StatefulWidget {
  const PhotoAnnotationScreen({
    super.key,
    required this.filePath,
  });

  final String filePath;

  @override
  State<PhotoAnnotationScreen> createState() => _PhotoAnnotationScreenState();
}

class _PhotoAnnotationScreenState extends State<PhotoAnnotationScreen> {
  final _repaintKey = GlobalKey();

  AnnotationType _tool = AnnotationType.freehand;
  String _color = '#FF0000';
  double _strokeWidth = 4.0;

  final List<PhotoAnnotation> _annotations = [];
  List<({double x, double y})> _currentPoints = [];
  int _idCounter = 0;

  bool _isSaving = false;

  static const _swatches = [
    (hex: '#FF0000', color: Color(0xFFFF0000)),
    (hex: '#FF8800', color: Color(0xFFFF8800)),
    (hex: '#FFFFFF', color: Color(0xFFFFFFFF)),
    (hex: '#000000', color: Color(0xFF000000)),
  ];

  // --- gesture handlers ---

  void _onPanStart(DragStartDetails d, Size size) {
    setState(() => _currentPoints = [_normalize(d.localPosition, size)]);
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    setState(
      () => _currentPoints = [..._currentPoints, _normalize(d.localPosition, size)],
    );
  }

  void _onPanEnd(DragEndDetails _) {
    if (_currentPoints.isEmpty) return;
    setState(() {
      _annotations.add(
        PhotoAnnotation(
          id: 'ann_${_idCounter++}',
          type: _tool,
          points: List.unmodifiable(_currentPoints),
          color: _color,
          strokeWidth: _strokeWidth,
        ),
      );
      _currentPoints = [];
    });
  }

  ({double x, double y}) _normalize(Offset local, Size size) =>
      (x: local.dx / size.width, y: local.dy / size.height);

  // --- actions ---

  void _undo() {
    if (_annotations.isEmpty) return;
    setState(() => _annotations.removeLast());
  }

  void _clear() => setState(() {
        _annotations.clear();
        _currentPoints = [];
      });

  Future<void> _confirm() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Image encoding failed');

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/annotated_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(bytes);

      if (mounted) Navigator.of(context).pop(outPath);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save annotation: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Annotate photo'),
        actions: [
          IconButton(
            onPressed: _annotations.isNotEmpty ? _undo : null,
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: _annotations.isNotEmpty ? _clear : null,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear all',
          ),
          TextButton(
            onPressed: _isSaving ? null : _confirm,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildCanvas()),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: (d) => _onPanStart(d, size),
          onPanUpdate: (d) => _onPanUpdate(d, size),
          onPanEnd: _onPanEnd,
          child: RepaintBoundary(
            key: _repaintKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(widget.filePath), fit: BoxFit.cover),
                CustomPaint(
                  painter: _AnnotationPainter(
                    annotations: _annotations,
                    currentPoints: _currentPoints,
                    currentTool: _tool,
                    currentColor: _color,
                    currentStroke: _strokeWidth,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: const Color(0xFF111111),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tool selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ToolButton(
                icon: Icons.gesture_rounded,
                label: 'Draw',
                selected: _tool == AnnotationType.freehand,
                onTap: () => setState(() => _tool = AnnotationType.freehand),
              ),
              _ToolButton(
                icon: Icons.arrow_forward_rounded,
                label: 'Arrow',
                selected: _tool == AnnotationType.arrow,
                onTap: () => setState(() => _tool = AnnotationType.arrow),
              ),
              _ToolButton(
                icon: Icons.circle_outlined,
                label: 'Circle',
                selected: _tool == AnnotationType.circle,
                onTap: () => setState(() => _tool = AnnotationType.circle),
              ),
              _ToolButton(
                icon: Icons.rectangle_outlined,
                label: 'Rect',
                selected: _tool == AnnotationType.rectangle,
                onTap: () => setState(() => _tool = AnnotationType.rectangle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Color palette + stroke toggle
          Row(
            children: [
              ..._swatches.map(
                (s) => GestureDetector(
                  onTap: () => setState(() => _color = s.hex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == s.hex ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(
                  () => _strokeWidth = _strokeWidth <= 4.0 ? 8.0 : 4.0,
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white38),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.line_weight_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _strokeWidth <= 4.0 ? 'Thin' : 'Thick',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter
// ---------------------------------------------------------------------------

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.annotations,
    required this.currentPoints,
    required this.currentTool,
    required this.currentColor,
    required this.currentStroke,
  });

  final List<PhotoAnnotation> annotations;
  final List<({double x, double y})> currentPoints;
  final AnnotationType currentTool;
  final String currentColor;
  final double currentStroke;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ann in annotations) {
      _drawAnnotation(canvas, size, ann);
    }
    if (currentPoints.length >= 2) {
      _drawAnnotation(
        canvas,
        size,
        PhotoAnnotation(
          id: '_preview',
          type: currentTool,
          points: currentPoints,
          color: currentColor,
          strokeWidth: currentStroke,
        ),
      );
    }
  }

  void _drawAnnotation(Canvas canvas, Size size, PhotoAnnotation ann) {
    final paint = Paint()
      ..color = _hex(ann.color)
      ..strokeWidth = ann.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final pts = ann.points;

    switch (ann.type) {
      case AnnotationType.freehand:
        if (pts.length >= 2) {
          final path = Path()
            ..moveTo(pts.first.x * size.width, pts.first.y * size.height);
          for (final p in pts.skip(1)) {
            path.lineTo(p.x * size.width, p.y * size.height);
          }
          canvas.drawPath(path, paint);
        }
      case AnnotationType.arrow:
        if (pts.length >= 2) {
          final p1 = Offset(pts.first.x * size.width, pts.first.y * size.height);
          final p2 = Offset(pts.last.x * size.width, pts.last.y * size.height);
          canvas.drawLine(p1, p2, paint);
          _arrowhead(canvas, p1, p2, paint);
        }
      case AnnotationType.circle:
        if (pts.length >= 2) {
          final p1 = Offset(pts.first.x * size.width, pts.first.y * size.height);
          final p2 = Offset(pts.last.x * size.width, pts.last.y * size.height);
          canvas.drawOval(Rect.fromPoints(p1, p2), paint);
        }
      case AnnotationType.rectangle:
        if (pts.length >= 2) {
          final p1 = Offset(pts.first.x * size.width, pts.first.y * size.height);
          final p2 = Offset(pts.last.x * size.width, pts.last.y * size.height);
          canvas.drawRect(Rect.fromPoints(p1, p2), paint);
        }
      case AnnotationType.text:
        break; // text handled via separate dialog; not in freehand path
    }
  }

  void _arrowhead(Canvas canvas, Offset from, Offset to, Paint paint) {
    const size = 16.0;
    final dir = (to - from).direction;
    canvas
      ..drawLine(to, to + Offset.fromDirection(dir + 2.6, size), paint)
      ..drawLine(to, to + Offset.fromDirection(dir - 2.6, size), paint);
  }

  Color _hex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) =>
      old.annotations != annotations ||
      old.currentPoints != currentPoints ||
      old.currentColor != currentColor ||
      old.currentStroke != currentStroke;
}

// ---------------------------------------------------------------------------
// Tool button
// ---------------------------------------------------------------------------

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.white54 : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

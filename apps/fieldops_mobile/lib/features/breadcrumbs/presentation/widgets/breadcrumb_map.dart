import 'dart:math';

import 'package:fieldops_mobile/features/breadcrumbs/domain/breadcrumb_repository.dart';
import 'package:flutter/material.dart';

/// Lightweight GPS trail map rendered with [CustomPaint].
///
/// Plots breadcrumb points as a polyline on a canvas, auto-fitting
/// to the bounding box of all points with padding. No external map
/// library required.
class BreadcrumbMap extends StatelessWidget {
  const BreadcrumbMap({
    super.key,
    required this.breadcrumbs,
    this.playbackIndex,
    this.trailColor,
    this.pointColor,
    this.activePointColor,
  });

  final List<Breadcrumb> breadcrumbs;

  /// If set, only draws the trail up to this index (for animated playback).
  final int? playbackIndex;

  final Color? trailColor;
  final Color? pointColor;
  final Color? activePointColor;

  @override
  Widget build(BuildContext context) {
    if (breadcrumbs.isEmpty) {
      return const Center(
        child: Text('No GPS data for this shift.'),
      );
    }

    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.grey.shade100,
        child: CustomPaint(
          painter: _BreadcrumbPainter(
            breadcrumbs: breadcrumbs,
            playbackIndex: playbackIndex ?? breadcrumbs.length - 1,
            trailColor: trailColor ?? theme.colorScheme.primary,
            pointColor: pointColor ?? theme.colorScheme.primary,
            activePointColor:
                activePointColor ?? theme.colorScheme.error,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BreadcrumbPainter extends CustomPainter {
  _BreadcrumbPainter({
    required this.breadcrumbs,
    required this.playbackIndex,
    required this.trailColor,
    required this.pointColor,
    required this.activePointColor,
  });

  final List<Breadcrumb> breadcrumbs;
  final int playbackIndex;
  final Color trailColor;
  final Color pointColor;
  final Color activePointColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (breadcrumbs.isEmpty || size.isEmpty) return;

    // Compute bounding box
    var minLat = breadcrumbs.first.latitude;
    var maxLat = breadcrumbs.first.latitude;
    var minLng = breadcrumbs.first.longitude;
    var maxLng = breadcrumbs.first.longitude;

    for (final bc in breadcrumbs) {
      minLat = min(minLat, bc.latitude);
      maxLat = max(maxLat, bc.latitude);
      minLng = min(minLng, bc.longitude);
      maxLng = max(maxLng, bc.longitude);
    }

    // Add padding (10% on each side)
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    final padLat = max(latRange * 0.1, 0.0005);
    final padLng = max(lngRange * 0.1, 0.0005);
    minLat -= padLat;
    maxLat += padLat;
    minLng -= padLng;
    maxLng += padLng;

    final effectiveLatRange = maxLat - minLat;
    final effectiveLngRange = maxLng - minLng;

    // Margin inside the canvas
    const margin = 24.0;
    final drawWidth = size.width - margin * 2;
    final drawHeight = size.height - margin * 2;

    Offset toCanvas(double lat, double lng) {
      final x = margin +
          (effectiveLngRange == 0
              ? drawWidth / 2
              : ((lng - minLng) / effectiveLngRange) * drawWidth);
      // Latitude is inverted (higher lat = higher on canvas)
      final y = margin +
          (effectiveLatRange == 0
              ? drawHeight / 2
              : ((maxLat - lat) / effectiveLatRange) * drawHeight);
      return Offset(x, y);
    }

    // Draw trail line
    final trailPaint = Paint()
      ..color = trailColor.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final visible = min(playbackIndex + 1, breadcrumbs.length);

    for (var i = 0; i < visible; i++) {
      final p = toCanvas(breadcrumbs[i].latitude, breadcrumbs[i].longitude);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, trailPaint);

    // Draw points
    final dotPaint = Paint()
      ..color = pointColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < visible; i++) {
      final p = toCanvas(breadcrumbs[i].latitude, breadcrumbs[i].longitude);
      canvas.drawCircle(p, 3, dotPaint);
    }

    // Start marker (green)
    if (breadcrumbs.isNotEmpty) {
      final start =
          toCanvas(breadcrumbs.first.latitude, breadcrumbs.first.longitude);
      canvas.drawCircle(
        start,
        8,
        Paint()
          ..color = Colors.green
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        start,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Active / current position marker
    if (visible > 0) {
      final current = toCanvas(
        breadcrumbs[visible - 1].latitude,
        breadcrumbs[visible - 1].longitude,
      );
      canvas.drawCircle(
        current,
        8,
        Paint()
          ..color = activePointColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        current,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BreadcrumbPainter oldDelegate) {
    return playbackIndex != oldDelegate.playbackIndex ||
        breadcrumbs != oldDelegate.breadcrumbs;
  }
}

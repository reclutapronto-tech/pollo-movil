import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A shimmer-style skeleton placeholder for loading states.
///
/// Replaces bare `CircularProgressIndicator()` with a more polished loading
/// experience that hints at the shape of the incoming content.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, this.itemCount = 3});

  /// Number of skeleton cards to display.
  final int itemCount;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: widget.itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => const _SkeletonCard(opacity: 0.14),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final opacity = 0.08 + (_animation.value * 0.12);
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, __) => _SkeletonCard(opacity: opacity),
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity * 0.4),
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBar(width: 180, height: 14, opacity: opacity, color: color),
          const SizedBox(height: 12),
          _SkeletonBar(width: 240, height: 10, opacity: opacity, color: color),
          const SizedBox(height: 8),
          _SkeletonBar(width: 140, height: 10, opacity: opacity, color: color),
          const SizedBox(height: 14),
          Row(
            children: [
              _SkeletonBar(
                width: 80,
                height: 32,
                opacity: opacity,
                color: color,
                borderRadius: FieldOpsRadius.full,
              ),
              const SizedBox(width: 10),
              _SkeletonBar(
                width: 80,
                height: 32,
                opacity: opacity,
                color: color,
                borderRadius: FieldOpsRadius.full,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.opacity,
    required this.color,
    this.borderRadius = 6,
  });

  final double width;
  final double height;
  final double opacity;
  final Color color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

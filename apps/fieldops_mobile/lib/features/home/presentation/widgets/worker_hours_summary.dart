import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Displays worker's hours: today, this week, this month.
/// Premium visual with progress bars and stat cards.
class WorkerHoursSummary extends StatelessWidget {
  const WorkerHoursSummary({
    super.key,
    this.hoursToday = 0,
    this.hoursThisWeek = 0,
    this.hoursThisMonth = 0,
    this.dailyTarget = 8,
    this.weeklyTarget = 40,
  });

  final double hoursToday;
  final double hoursThisWeek;
  final double hoursThisMonth;
  final double dailyTarget;
  final double weeklyTarget;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Hours summary: ${hoursToday.toStringAsFixed(1)} today, '
          '${hoursThisWeek.toStringAsFixed(1)} this week, '
          '${hoursThisMonth.toStringAsFixed(1)} this month',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(FieldOpsSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceWhite,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
          border: Border.all(color: palette.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 20, color: palette.steel),
                const SizedBox(width: 8),
                Text('Your hours', style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: FieldOpsSpacing.base),

            // 3 stat cards in a row
            Row(
              children: [
                Expanded(
                  child: _HourCard(
                    label: 'Today',
                    hours: hoursToday,
                    target: dailyTarget,
                    color: _colorForProgress(hoursToday / dailyTarget, palette),
                    palette: palette,
                    textTheme: textTheme,
                  ),
                ),
                const SizedBox(width: FieldOpsSpacing.sm),
                Expanded(
                  child: _HourCard(
                    label: 'This week',
                    hours: hoursThisWeek,
                    target: weeklyTarget,
                    color: _colorForProgress(
                        hoursThisWeek / weeklyTarget, palette),
                    palette: palette,
                    textTheme: textTheme,
                  ),
                ),
                const SizedBox(width: FieldOpsSpacing.sm),
                Expanded(
                  child: _HourCard(
                    label: 'This month',
                    hours: hoursThisMonth,
                    target: null,
                    color: palette.steel,
                    palette: palette,
                    textTheme: textTheme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForProgress(double progress, FieldOpsPalette palette) {
    if (progress >= 1.0) return palette.danger; // OT territory
    if (progress >= 0.875) return palette.signal; // Approaching OT
    return palette.success;
  }
}

class _HourCard extends StatelessWidget {
  const _HourCard({
    required this.label,
    required this.hours,
    required this.target,
    required this.color,
    required this.palette,
    required this.textTheme,
  });

  final String label;
  final double hours;
  final double? target;
  final Color color;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final progress = target != null ? (hours / target!).clamp(0.0, 1.0) : null;

    return Container(
      padding: const EdgeInsets.all(FieldOpsSpacing.md),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            '${hours.toStringAsFixed(1)}h',
            style: textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: palette.border,
                color: color,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${target!.toStringAsFixed(0)}h target',
              style: textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

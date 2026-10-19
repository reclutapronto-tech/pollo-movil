import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/budgeting/domain/budget_repository.dart';
import 'package:flutter/material.dart';

/// Card showing budget vs actual for a job.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.budget,
    this.compact = false,
  });

  final JobBudgetSummary budget;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budget.jobName,
                      style: textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (budget.jobCode.isNotEmpty)
                      Text(
                        budget.jobCode,
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.steel,
                        ),
                      ),
                  ],
                ),
              ),
              if (budget.isOverBudget)
                _StatusBadge(
                  label: 'Over Budget',
                  color: palette.danger,
                  textTheme: textTheme,
                )
              else if (budget.isApproachingLimit)
                _StatusBadge(
                  label: 'Warning',
                  color: palette.signal,
                  textTheme: textTheme,
                )
              else
                _StatusBadge(
                  label: 'On Track',
                  color: palette.success,
                  textTheme: textTheme,
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Hours progress
          _ProgressRow(
            label: 'Hours',
            current: budget.actualHours,
            total: budget.budgetedHours,
            unit: 'h',
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 12),

          // Cost progress
          _ProgressRow(
            label: 'Cost',
            current: budget.actualCost,
            total: budget.budgetedCost,
            unit: '\$',
            isCurrency: true,
            palette: palette,
            textTheme: textTheme,
          ),

          if (!compact) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Variance row
            Row(
              children: [
                _VarianceChip(
                  label: 'Hours',
                  variance: budget.hoursVariance,
                  unit: 'h',
                  palette: palette,
                  textTheme: textTheme,
                ),
                const SizedBox(width: 12),
                _VarianceChip(
                  label: 'Cost',
                  variance: budget.costVariance,
                  unit: '\$',
                  isCurrency: true,
                  palette: palette,
                  textTheme: textTheme,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.current,
    required this.total,
    required this.unit,
    required this.palette,
    required this.textTheme,
    this.isCurrency = false,
  });

  final String label;
  final double current;
  final double total;
  final String unit;
  final FieldOpsPalette palette;
  final TextTheme textTheme;
  final bool isCurrency;

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
    final color = percent >= 1.0
        ? palette.danger
        : percent >= 0.8
            ? palette.signal
            : palette.success;

    String formatValue(double value) {
      if (isCurrency) return '\$${value.toStringAsFixed(0)}';
      return '${value.toStringAsFixed(1)}h';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: textTheme.bodyMedium),
            Text(
              '${formatValue(current)} / ${formatValue(total)}',
              style: textTheme.bodySmall?.copyWith(
                color: palette.steel,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(FieldOpsRadius.full),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: palette.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _VarianceChip extends StatelessWidget {
  const _VarianceChip({
    required this.label,
    required this.variance,
    required this.unit,
    required this.palette,
    required this.textTheme,
    this.isCurrency = false,
  });

  final String label;
  final double variance;
  final String unit;
  final FieldOpsPalette palette;
  final TextTheme textTheme;
  final bool isCurrency;

  @override
  Widget build(BuildContext context) {
    final isOver = variance > 0;
    final color = isOver ? palette.danger : palette.success;
    final sign = isOver ? '+' : '';

    String formatValue(double value) {
      if (isCurrency) return '\$${value.abs().toStringAsFixed(0)}';
      return '${value.abs().toStringAsFixed(1)}h';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOver ? Icons.trending_up : Icons.trending_down,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $sign${formatValue(variance)}',
            style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.textTheme,
  });

  final String label;
  final Color color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FieldOpsRadius.full),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

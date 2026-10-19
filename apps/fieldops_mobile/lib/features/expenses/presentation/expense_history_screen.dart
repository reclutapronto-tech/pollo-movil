import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/expenses/domain/expense_repository.dart';
import 'package:fieldops_mobile/features/expenses/presentation/expense_history_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpenseHistoryScreen extends ConsumerWidget {
  const ExpenseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(expenseHistoryProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expenses'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(expenseHistoryProvider.notifier).reload(),
        child: historyState.when(
          data: (expenses) {
            if (expenses.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 120),
                  _EmptyState(palette: palette, textTheme: textTheme),
                ],
              );
            }

            // Group by month
            final grouped = <String, List<ExpenseRecord>>{};
            for (final expense in expenses) {
              final key = _monthKey(expense.createdAt);
              (grouped[key] ??= []).add(expense);
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: grouped.length,
              itemBuilder: (context, sectionIndex) {
                final month = grouped.keys.elementAt(sectionIndex);
                final items = grouped[month]!;
                final total = items.fold<double>(
                  0.0,
                  (sum, e) => sum + e.amount,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sectionIndex > 0) const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(month, style: textTheme.titleMedium),
                        Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: textTheme.titleMedium?.copyWith(
                            color: palette.signal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...items.map(
                      (expense) => _ExpenseCard(
                        expense: expense,
                        palette: palette,
                        textTheme: textTheme,
                      ),
                    ),
                  ],
                );
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 4),
          ),
          error: (error, _) {
            final message = error is ExpenseRepositoryException
                ? error.message
                : 'Could not load expenses.';
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 120),
                _ErrorState(message: message, textTheme: textTheme),
              ],
            );
          },
        ),
      ),
    );
  }

  String _monthKey(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.palette,
    required this.textTheme,
  });

  final ExpenseRecord expense;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  static const _categoryIcons = <String, IconData>{
    'materials': Icons.inventory_2_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'tools': Icons.construction_rounded,
    'meals': Icons.restaurant_rounded,
    'other': Icons.receipt_long_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _categoryIcons[expense.category] ?? Icons.receipt_long_rounded;
    final statusColor = switch (expense.status) {
      'approved' => palette.success,
      'denied' => palette.danger,
      _ => palette.signal,
    };
    final date = expense.createdAt;
    final dateStr = '${date.month}/${date.day}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: palette.steel),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.jobName, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  [
                    expense.category[0].toUpperCase() +
                        expense.category.substring(1),
                    if (expense.vendor != null && expense.vendor!.isNotEmpty)
                      expense.vendor!,
                    dateStr,
                  ].join(' \u00B7 '),
                  style: textTheme.bodySmall?.copyWith(color: palette.steel),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${expense.amount.toStringAsFixed(2)}',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                ),
                child: Text(
                  expense.status.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.textTheme});

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.receipt_long_rounded,
          size: 48,
          color: palette.steel.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 12),
        Text('No expenses yet', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Expenses you submit for jobs will appear here.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: palette.steel),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.textTheme});

  final String message;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 48,
          color: Colors.black.withValues(alpha: 0.32),
        ),
        const SizedBox(height: 12),
        Text('Expenses unavailable', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

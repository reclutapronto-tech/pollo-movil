import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/history/domain/history_repository.dart';
import 'package:fieldops_mobile/features/history/presentation/history_controller.dart';
import 'package:fieldops_mobile/features/timecards/presentation/timecards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// History tab — worker's personal record of all shifts, hours, photos.
///
/// Shows week/month summary cards at top, followed by a timeline list
/// of individual clock events grouped by date.
class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(historyControllerProvider);
    final weekSummary = ref.watch(weekSummaryProvider);
    final monthSummary = ref.watch(monthSummaryProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work History'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TimecardsScreen(),
                ),
              );
            },
            icon: Icon(Icons.description_rounded, size: 18, color: palette.signal),
            label: Text(
              'Timecards',
              style: textTheme.labelLarge?.copyWith(color: palette.signal),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(weekSummaryProvider);
          ref.invalidate(monthSummaryProvider);
          await ref.read(historyControllerProvider.notifier).reload();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ─── Summary Cards ────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'This Week',
                        summary: weekSummary,
                        palette: palette,
                        textTheme: textTheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'This Month',
                        summary: monthSummary,
                        palette: palette,
                        textTheme: textTheme,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── Section Header ───────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Recent Shifts', style: textTheme.titleMedium),
              ),
            ),

            // ─── History List ─────────────────────────────
            historyState.when(
              data: (entries) {
                if (entries.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(palette: palette, textTheme: textTheme),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HistoryEntryCard(
                          entry: entries[index],
                          palette: palette,
                          textTheme: textTheme,
                        ),
                      ),
                      childCount: entries.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: SkeletonLoader(itemCount: 5),
                ),
              ),
              error: (error, _) {
                final msg = error is HistoryRepositoryException
                    ? error.message
                    : 'Could not load history.';
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(message: msg, textTheme: textTheme),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.summary,
    required this.palette,
    required this.textTheme,
  });

  final String title;
  final AsyncValue<HistorySummary> summary;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.border, width: 0.5),
      ),
      child: summary.when(
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.labelMedium),
            const SizedBox(height: 8),
            Text(
              '${s.totalHours.toStringAsFixed(1)}h',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _MiniStat(
                  label: 'Reg',
                  value: '${s.regularHours.toStringAsFixed(1)}h',
                  color: palette.success,
                  textTheme: textTheme,
                ),
                const SizedBox(width: 8),
                _MiniStat(
                  label: 'OT',
                  value: '${s.otHours.toStringAsFixed(1)}h',
                  color: palette.signal,
                  textTheme: textTheme,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${s.totalJobs} job${s.totalJobs == 1 ? '' : 's'} • ${s.totalPhotos} photo${s.totalPhotos == 1 ? '' : 's'}',
              style: textTheme.bodySmall,
            ),
          ],
        ),
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.labelMedium),
            const SizedBox(height: 12),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
        error: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.labelMedium),
            const SizedBox(height: 8),
            Text('—', style: textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Unavailable', style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.textTheme,
  });

  final String label;
  final String value;
  final Color color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $value',
          style: textTheme.labelSmall?.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

// ─── History Entry Card ───────────────────────────────────────

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({
    required this.entry,
    required this.palette,
    required this.textTheme,
  });

  final HistoryEntry entry;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayHour:$m $period';
  }

  String _formatDate(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final timeRange = entry.clockOutAt != null
        ? '${_formatTime(entry.clockInAt)} – ${_formatTime(entry.clockOutAt!)}'
        : '${_formatTime(entry.clockInAt)} – Active';

    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.jobName, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(entry.date),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // Hours badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: entry.isActive
                      ? palette.success.withValues(alpha: 0.1)
                      : palette.muted,
                  borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                ),
                child: Text(
                  entry.isActive
                      ? 'Active'
                      : '${entry.totalHours.toStringAsFixed(1)}h',
                  style: textTheme.labelSmall?.copyWith(
                    color: entry.isActive ? palette.success : palette.slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Details row
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _DetailChip(
                icon: Icons.schedule_rounded,
                label: timeRange,
                palette: palette,
              ),
              if (entry.photosCount > 0)
                _DetailChip(
                  icon: Icons.camera_alt_outlined,
                  label: '${entry.photosCount} photo${entry.photosCount == 1 ? '' : 's'}',
                  palette: palette,
                ),
              if (entry.tasksCompleted > 0)
                _DetailChip(
                  icon: Icons.task_alt_rounded,
                  label: '${entry.tasksCompleted} task${entry.tasksCompleted == 1 ? '' : 's'}',
                  palette: palette,
                ),
              if (entry.otHours > 0)
                _DetailChip(
                  icon: Icons.more_time_rounded,
                  label: '${entry.otHours.toStringAsFixed(1)}h OT',
                  palette: palette,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: palette.steel),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

// ─── Empty & Error States ─────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.textTheme});

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 48,
              color: palette.steel.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No history yet', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Your past shifts, hours, and photos will appear here\nonce you clock in and complete work.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: palette.steel),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.textTheme});

  final String message;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48,
              color: Colors.black.withValues(alpha: 0.32)),
          const SizedBox(height: 12),
          Text('History unavailable', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/core/data/pending_count_provider.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quick stats row: Tasks ready, Photos saved, Pending sync.
///
/// Enhancement over spec: shows actionable counts instead of just numbers.
class QuickStatsRow extends ConsumerWidget {
  const QuickStatsRow({
    super.key,
    required this.jobsState,
    required this.isClockedIn,
  });

  final AsyncValue<List<JobSummary>> jobsState;
  final bool isClockedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final pendingAsync = ref.watch(pendingEventCountProvider);
    final photoDraftsAsync = ref.watch(pendingPhotoDraftCountProvider);

    final totalTasks = jobsState.value
            ?.fold<int>(0, (sum, job) => sum + job.taskCount) ??
        0;
    final pendingCount = pendingAsync.value ?? 0;
    final draftCount = photoDraftsAsync.value ?? 0;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.checklist_rounded,
            label: 'Tasks',
            value: '$totalTasks',
            color: palette.signal,
            palette: palette,
            textTheme: textTheme,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.photo_library_outlined,
            label: 'Saved',
            value: '$draftCount',
            color: draftCount > 0 ? palette.signal : palette.steel,
            palette: palette,
            textTheme: textTheme,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.sync_rounded,
            label: 'Queued',
            value: '$pendingCount',
            color: pendingCount > 0 ? palette.danger : palette.success,
            palette: palette,
            textTheme: textTheme,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.palette,
    required this.textTheme,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceWhite,
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
          border: Border.all(color: palette.border, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(color: palette.steel),
            ),
          ],
        ),
      ),
    );
  }
}

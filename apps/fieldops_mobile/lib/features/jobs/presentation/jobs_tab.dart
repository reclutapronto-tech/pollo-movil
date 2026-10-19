import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_with_safety.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/clock_error_panel.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/jobs_error_state.dart';
import 'package:fieldops_mobile/features/home/presentation/worker_hours_controller.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/jobs/domain/jobs_repository.dart';
import 'package:fieldops_mobile/features/jobs/presentation/job_detail_screen.dart';
import 'package:fieldops_mobile/features/jobs/presentation/jobs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Jobs tab — all assigned jobs in one place.
///
/// Each card taps through to [JobDetailScreen] for the full drill-down
/// with tasks, photos, expenses, safety, and route.
class JobsTab extends ConsumerWidget {
  const JobsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsState = ref.watch(jobsControllerProvider);
    final clockState = ref.watch(clockControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Jobs'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref
                .read(jobsControllerProvider.notifier)
                .reload()
                .catchError((_) {}),
            ref
                .read(workerHoursControllerProvider.notifier)
                .reload()
                .catchError((_) {}),
          ]);
        },
        child: jobsState.when(
          data: (jobs) {
            final hasClockError = clockState.hasError;
            final errorOffset = hasClockError ? 1 : 0;

            if (jobs.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (hasClockError) ...[
                    ClockErrorPanel(state: clockState),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 120),
                  _EmptyState(palette: palette, textTheme: textTheme),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: jobs.length + errorOffset,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (hasClockError && index == 0) {
                  return ClockErrorPanel(state: clockState);
                }
                final job = jobs[index - errorOffset];
                final isClockedInHere = clockState.isClockedInFor(job.jobId);

                return _JobListCard(
                  job: job,
                  isClockedIn: isClockedInHere,
                  isAnyJobActive: clockState.isClockedIn,
                  palette: palette,
                  textTheme: textTheme,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => JobDetailScreen(
                          job: job,
                          clockState: clockState,
                        ),
                      ),
                    );
                  },
                  onClockIn: () {
                    HapticFeedback.mediumImpact();
                    guardedClockIn(
                      context,
                      ref,
                      jobId: job.jobId,
                      jobName: job.jobName,
                    );
                  },
                );
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 4),
          ),
          error: (error, _) {
            final repositoryError = error is JobsRepositoryException
                ? error
                : const JobsRepositoryException.unknown();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 120),
                JobsErrorState(
                  error: repositoryError,
                  onRetry: () =>
                      ref.read(jobsControllerProvider.notifier).reload(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Job List Card ────────────────────────────────────────────

class _JobListCard extends StatelessWidget {
  const _JobListCard({
    required this.job,
    required this.isClockedIn,
    required this.isAnyJobActive,
    required this.palette,
    required this.textTheme,
    required this.onTap,
    required this.onClockIn,
  });

  final JobSummary job;
  final bool isClockedIn;
  final bool isAnyJobActive;
  final FieldOpsPalette palette;
  final TextTheme textTheme;
  final VoidCallback onTap;
  final VoidCallback onClockIn;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${job.jobName}. ${job.taskCount} tasks. '
          '${isClockedIn ? "Currently clocked in." : "Tap for details."}',
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isClockedIn
                            ? palette.success.withValues(alpha: 0.12)
                            : palette.signal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isClockedIn
                            ? Icons.verified_user_rounded
                            : Icons.work_history_rounded,
                        color: isClockedIn ? palette.success : palette.signal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.jobName, style: textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            '${job.taskCount} task${job.taskCount == 1 ? '' : 's'} • ${job.geofenceRadiusM}m geofence',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isClockedIn
                            ? palette.success.withValues(alpha: 0.12)
                            : palette.muted,
                        borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                      ),
                      child: Text(
                        isClockedIn ? 'Active' : 'Assigned',
                        style: textTheme.labelSmall?.copyWith(
                          color: isClockedIn ? palette.success : palette.steel,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                // Quick clock-in when not clocked in anywhere
                if (!isAnyJobActive) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onClockIn,
                      icon: const Icon(Icons.timer_outlined, size: 20),
                      label: const Text('Clock in'),
                    ),
                  ),
                ],

                // Chevron hint for detail
                if (isAnyJobActive) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'View details',
                        style: textTheme.labelMedium?.copyWith(
                          color: palette.signal,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: palette.signal),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
    return Column(
      children: [
        Icon(Icons.work_off_rounded, size: 48,
            color: palette.steel.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text('No jobs assigned', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Jobs will appear here when your supervisor assigns work.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: palette.steel),
        ),
      ],
    );
  }
}


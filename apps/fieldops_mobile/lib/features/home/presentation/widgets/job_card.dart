import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_capture_screen.dart';
import 'package:fieldops_mobile/features/camera/presentation/photo_drafts_screen.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/expenses/presentation/expense_capture_screen.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/breadcrumbs/presentation/breadcrumb_playback_screen.dart';
import 'package:fieldops_mobile/features/safety/presentation/safety_checklist_screen.dart';
import 'package:fieldops_mobile/features/tasks/presentation/task_list_screen.dart';
import 'package:fieldops_mobile/features/tasks/presentation/tasks_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JobCard extends ConsumerWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.clockState,
    required this.onClockIn,
  });

  final JobSummary job;
  final ClockInState clockState;
  final Future<void> Function({required String jobId, required String jobName})
  onClockIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final draftCountAsync = ref.watch(
      pendingPhotoDraftCountForJobProvider(job.jobId),
    );
    final draftCount = draftCountAsync.value ?? 0;
    final taskLabel = job.taskCount == 1
        ? '1 task ready'
        : '${job.taskCount} tasks ready';
    final isSubmitting = clockState.isSubmitting(job.jobId);
    final isClockedIn = clockState.isClockedInFor(job.jobId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.signal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.work_history_rounded,
                    color: palette.signal,
                    semanticLabel: 'Job',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(job.jobName, style: textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(icon: Icons.task_alt_rounded, label: taskLabel),
                _InfoChip(
                  icon: Icons.pin_drop_outlined,
                  label: '${job.geofenceRadiusM}m geofence',
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: isSubmitting
                    ? 'Clocking in to ${job.jobName}'
                    : isClockedIn
                    ? 'Clocked in to ${job.jobName}'
                    : 'Clock in to ${job.jobName}',
                child: ElevatedButton.icon(
                  onPressed: isSubmitting || isClockedIn
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          onClockIn(jobId: job.jobId, jobName: job.jobName);
                        },
                  icon: isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.slate,
                          ),
                        )
                      : Icon(
                          isClockedIn
                              ? Icons.verified_rounded
                              : Icons.timer_outlined,
                        ),
                  label: Text(
                    isSubmitting
                        ? 'Clocking in...'
                        : isClockedIn
                        ? 'Clocked in'
                        : 'Clock in',
                  ),
                ),
              ),
            ),
            if (isClockedIn) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'View tasks for ${job.jobName}',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.steel,
                          side: BorderSide(
                            color: palette.steel.withValues(alpha: 0.3),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ProviderScope(
                                overrides: [
                                  activeTaskJobIdProvider.overrideWithValue(
                                    job.jobId,
                                  ),
                                ],
                                child: TaskListScreen(
                                  jobId: job.jobId,
                                  jobName: job.jobName,
                                ),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.checklist_rounded),
                        label: Text('${job.taskCount} tasks'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Take proof photo for ${job.jobName}',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.signal,
                          side: BorderSide(
                            color: palette.signal.withValues(alpha: 0.4),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: () async {
                          final result = await Navigator.of(context)
                              .push<PhotoCaptureResult?>(
                                MaterialPageRoute<PhotoCaptureResult?>(
                                  builder: (_) => CameraCaptureScreen(
                                    jobId: job.jobId,
                                    jobName: job.jobName,
                                    allowSaveForLater: true,
                                  ),
                                ),
                              );

                          if (!context.mounted || result == null) {
                            return;
                          }

                          final message = result.isSavedForLater
                              ? 'Photo saved on device. Send it later from Saved photos.'
                              : 'Photo uploaded for ${job.jobName}.';
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        },
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: Text(
                          draftCount > 0
                              ? 'Photo ($draftCount saved)'
                              : 'Photo',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (draftCount > 0) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.signal,
                      side: BorderSide(
                        color: palette.signal.withValues(alpha: 0.28),
                      ),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PhotoDraftsScreen(
                            jobId: job.jobId,
                            jobName: job.jobName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(
                      draftCount == 1
                          ? '1 saved photo'
                          : '$draftCount saved photos',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  button: true,
                  label: 'Submit expense for ${job.jobName}',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.steel,
                      side: BorderSide(
                        color: palette.steel.withValues(alpha: 0.25),
                      ),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) => ExpenseCaptureScreen(
                            jobId: job.jobId,
                            jobName: job.jobName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Submit Expense'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  button: true,
                  label: 'Safety checklist for ${job.jobName}',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.success,
                      side: BorderSide(
                        color: palette.success.withValues(alpha: 0.3),
                      ),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) => SafetyChecklistScreen(
                            jobId: job.jobId,
                            jobName: job.jobName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shield_rounded, size: 18),
                    label: const Text('Safety Checklist'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  button: true,
                  label: 'View shift route for ${job.jobName}',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.steel,
                      side: BorderSide(
                        color: palette.steel.withValues(alpha: 0.2),
                      ),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    onPressed: () {
                      final today = DateTime.now();
                      final shiftDate =
                          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BreadcrumbPlaybackScreen(
                            shiftDate: shiftDate,
                            jobName: job.jobName,
                            jobId: job.jobId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: const Text('View Route'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: palette.canvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: palette.steel),
            const SizedBox(width: 8),
            Text(label, style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

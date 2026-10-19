import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/auth/domain/user_role.dart';
import 'package:fieldops_mobile/features/breadcrumbs/presentation/breadcrumb_playback_screen.dart';
import 'package:fieldops_mobile/features/budgeting/presentation/job_budget_screen.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_capture_screen.dart';
import 'package:fieldops_mobile/features/camera/presentation/photo_drafts_screen.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_with_safety.dart';
import 'package:fieldops_mobile/features/clock/presentation/widgets/shift_wrapup_dialog.dart';
import 'package:fieldops_mobile/features/expenses/presentation/expense_capture_screen.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_request_screen.dart';
import 'package:fieldops_mobile/features/safety/presentation/safety_checklist_screen.dart';
import 'package:fieldops_mobile/features/tasks/presentation/task_list_screen.dart';
import 'package:fieldops_mobile/features/tasks/presentation/tasks_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full job detail screen — drill-down from the Jobs tab.
///
/// Shows job info header, all action buttons (tasks, photo, expense,
/// safety, route), clock in/out, and OT request. This replaces the
/// packed job card approach with a dedicated screen.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({
    super.key,
    required this.job,
    required this.clockState,
  });

  final JobSummary job;
  final ClockState clockState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final role = ref.watch(userRoleProvider);
    final isClockedInHere = clockState.isClockedInFor(job.jobId);
    final isSubmitting = clockState.isSubmitting(job.jobId);
    final draftCountAsync =
        ref.watch(pendingPhotoDraftCountForJobProvider(job.jobId));
    final draftCount = draftCountAsync.value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(job.jobName),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── Job Info Header ────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.surfaceWhite,
              borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isClockedInHere
                            ? palette.success.withValues(alpha: 0.12)
                            : palette.signal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isClockedInHere
                            ? Icons.verified_user_rounded
                            : Icons.work_history_rounded,
                        color:
                            isClockedInHere ? palette.success : palette.signal,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.jobName, style: textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          Text(
                            isClockedInHere ? 'Currently active' : 'Assigned',
                            style: textTheme.bodyMedium?.copyWith(
                              color: isClockedInHere
                                  ? palette.success
                                  : palette.steel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoChip(
                      icon: Icons.task_alt_rounded,
                      label: '${job.taskCount} task${job.taskCount == 1 ? '' : 's'}',
                      palette: palette,
                    ),
                    _InfoChip(
                      icon: Icons.pin_drop_outlined,
                      label: '${job.geofenceRadiusM}m geofence',
                      palette: palette,
                    ),
                    if (draftCount > 0)
                      _InfoChip(
                        icon: Icons.photo_library_outlined,
                        label: '$draftCount saved photo${draftCount == 1 ? '' : 's'}',
                        palette: palette,
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── Clock In / Out ─────────────────────────────
          if (!isClockedInHere && !clockState.isClockedIn)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        guardedClockIn(
                          context,
                          ref,
                          jobId: job.jobId,
                          jobName: job.jobName,
                        );
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.timer_outlined),
                label: Text(isSubmitting ? 'Clocking in...' : 'Clock In'),
              ),
            ),

          if (isClockedInHere) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.danger,
                  side: BorderSide(
                    color: palette.danger.withValues(alpha: 0.4),
                  ),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                  ),
                ),
                onPressed: () async {
                  final wrapup = await ShiftWrapupDialog.show(
                    context,
                    jobName: job.jobName,
                    clockedInAt: clockState.clockedInAt,
                  );
                  if (wrapup == null) return;
                  await ref
                      .read(clockControllerProvider.notifier)
                      .clockOut();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Clock Out'),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ─── Action Grid ────────────────────────────────
          Text('Actions', style: textTheme.titleMedium),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.checklist_rounded,
            title: 'Tasks',
            subtitle: '${job.taskCount} task${job.taskCount == 1 ? '' : 's'} assigned',
            color: palette.signal,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProviderScope(
                    overrides: [
                      activeTaskJobIdProvider.overrideWithValue(job.jobId),
                    ],
                    child: TaskListScreen(
                      jobId: job.jobId,
                      jobName: job.jobName,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          _ActionTile(
            icon: Icons.camera_alt_rounded,
            title: 'Take Proof Photo',
            subtitle: draftCount > 0
                ? '$draftCount photo${draftCount == 1 ? '' : 's'} saved locally'
                : 'Capture proof photos for this job',
            color: palette.signal,
            onTap: () async {
              final result =
                  await Navigator.of(context).push<PhotoCaptureResult?>(
                MaterialPageRoute<PhotoCaptureResult?>(
                  builder: (_) => CameraCaptureScreen(
                    jobId: job.jobId,
                    jobName: job.jobName,
                    allowSaveForLater: true,
                  ),
                ),
              );
              if (!context.mounted || result == null) return;
              final message = result.isSavedForLater
                  ? 'Photo saved on device.'
                  : 'Photo uploaded for ${job.jobName}.';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
          ),

          if (draftCount > 0) ...[
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.photo_library_outlined,
              title: 'Saved Photos',
              subtitle: '$draftCount photo${draftCount == 1 ? '' : 's'} waiting to send',
              color: palette.signal,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoDraftsScreen(
                      jobId: job.jobId,
                      jobName: job.jobName,
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 10),

          _ActionTile(
            icon: Icons.receipt_long_rounded,
            title: 'Submit Expense',
            subtitle: 'Capture a receipt for this job',
            color: palette.steel,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => ExpenseCaptureScreen(
                    jobId: job.jobId,
                    jobName: job.jobName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          _ActionTile(
            icon: Icons.shield_rounded,
            title: 'Safety Checklist',
            subtitle: 'Complete safety sign-off',
            color: palette.success,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => SafetyChecklistScreen(
                    jobId: job.jobId,
                    jobName: job.jobName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          _ActionTile(
            icon: Icons.route_rounded,
            title: 'View Route',
            subtitle: 'GPS breadcrumb trail playback',
            color: palette.steel,
            onTap: () {
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
          ),

          if (role.canManageCrew) ...[
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Job Budget',
              subtitle: 'Budget vs actual hours and cost',
              color: const Color(0xFF059669),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => JobBudgetScreen(
                      jobId: job.jobId,
                      jobName: job.jobName,
                    ),
                  ),
                );
              },
            ),
          ],

          if (isClockedInHere) ...[
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.more_time_rounded,
              title: 'Request Overtime',
              subtitle: 'Submit OT verification',
              color: palette.danger,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => OTRequestScreen(
                      jobId: job.jobId,
                      jobName: job.jobName,
                    ),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(FieldOpsRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: palette.steel),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: title,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.steel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

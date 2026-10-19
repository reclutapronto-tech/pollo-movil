import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/clock/presentation/widgets/shift_wrapup_dialog.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_snapshot.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/clock_error_panel.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/clock_status_panel.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/pending_actions_card.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/quick_stats_row.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/sync_status_bar.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/sync_status_pill.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/worker_hours_summary.dart';
import 'package:fieldops_mobile/features/home/presentation/worker_hours_controller.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/jobs/presentation/jobs_controller.dart';
import 'package:fieldops_mobile/features/overtime/presentation/widgets/ot_prompt_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Home tab — the worker's main dashboard.
///
/// Shows greeting, clock status, active job, quick stats, and pending actions.
/// Designed for one-glance status check + fastest path to clock in/out.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key, this.email});

  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clockState = ref.watch(clockControllerProvider);
    final workerHoursState = ref.watch(workerHoursControllerProvider);
    final jobsState = ref.watch(jobsControllerProvider);
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;

    final clockPanel = ClockStatusPanel(
      state: clockState,
      onClockOut: clockState.isClockedIn
          ? () async {
              final wrapup = await ShiftWrapupDialog.show(
                context,
                jobName: clockState.activeJobName ?? '',
                clockedInAt: clockState.clockedInAt,
              );
              if (wrapup == null) return;
              await ref.read(clockControllerProvider.notifier).clockOut();
            }
          : null,
      onBreakToggle: clockState.isClockedIn
          ? () {
              if (clockState.isOnBreak) {
                ref.read(clockControllerProvider.notifier).endBreak();
              } else {
                ref.read(clockControllerProvider.notifier).startBreak();
              }
            }
          : null,
    );

    Future<void> onRefresh() async {
      await Future.wait([
        ref.read(jobsControllerProvider.notifier).reload().catchError((_) {}),
        ref
            .read(workerHoursControllerProvider.notifier)
            .reload()
            .catchError((_) {}),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FieldOps'),
        centerTitle: false,
        actions: const [SyncStatusPill()],
      ),
      body: Column(
        children: [
          const SyncStatusBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: clockState.isClockedIn
                  ? _ClockedInView(
                      clockPanel: clockPanel,
                      clockState: clockState,
                      workerHoursState: workerHoursState,
                      jobsState: jobsState,
                      email: email,
                      palette: palette,
                      textTheme: textTheme,
                    )
                  : _ClockedOutView(
                      clockPanel: clockPanel,
                      clockState: clockState,
                      workerHoursState: workerHoursState,
                      jobsState: jobsState,
                      email: email,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clocked-OUT view (30-second rule): greeting + giant clock card ──
// Everything else is hidden behind an expandable "More" tile.

class _ClockedOutView extends StatelessWidget {
  const _ClockedOutView({
    required this.clockPanel,
    required this.clockState,
    required this.workerHoursState,
    required this.jobsState,
    required this.email,
  });

  final Widget clockPanel;
  final ClockState clockState;
  final AsyncValue<WorkerHoursSnapshot> workerHoursState;
  final AsyncValue<List<JobSummary>> jobsState;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Giant clock card fills at least 60% of the available height so the
        // primary action is always above the fold — even on a 5" phone in
        // gloves and sunlight. "More" reveals secondary surfaces on tap.
        final minClockHeight = constraints.maxHeight * 0.60;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GreetingHeader(email: email),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minClockHeight),
                child: Center(child: clockPanel),
              ),
              if (clockState.hasError) ...[
                const SizedBox(height: 14),
                ClockErrorPanel(state: clockState),
              ],
              const SizedBox(height: 16),
              _MoreTile(
                children: [
                  _WorkerHoursSection(state: workerHoursState),
                  const SizedBox(height: 16),
                  QuickStatsRow(
                    jobsState: jobsState,
                    isClockedIn: false,
                  ),
                  const SizedBox(height: 16),
                  const OTPromptBanner(),
                  const PendingActionsCard(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Clocked-IN view: full stack (unchanged ordering) ─────────────────

class _ClockedInView extends StatelessWidget {
  const _ClockedInView({
    required this.clockPanel,
    required this.clockState,
    required this.workerHoursState,
    required this.jobsState,
    required this.email,
    required this.palette,
    required this.textTheme,
  });

  final Widget clockPanel;
  final ClockState clockState;
  final AsyncValue<WorkerHoursSnapshot> workerHoursState;
  final AsyncValue<List<JobSummary>> jobsState;
  final String? email;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        _GreetingHeader(email: email),
        const SizedBox(height: 20),
        clockPanel,
        if (clockState.hasError) ...[
          const SizedBox(height: 14),
          ClockErrorPanel(state: clockState),
        ],
        const SizedBox(height: 16),
        _WorkerHoursSection(state: workerHoursState),
        const SizedBox(height: 16),
        QuickStatsRow(
          jobsState: jobsState,
          isClockedIn: true,
        ),
        const SizedBox(height: 16),
        const OTPromptBanner(),
        _ActiveJobCard(
          jobName: clockState.activeJobName ?? 'Unknown job',
          clockedInAt: clockState.clockedInAt,
          palette: palette,
          textTheme: textTheme,
        ),
        const SizedBox(height: 16),
        const PendingActionsCard(),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─── Collapsible "More" section (30-second-rule helper) ──────────────

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Theme(
      // Strip ExpansionTile's default divider so the card edges stay clean.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      // The ExpansionTile renders a ListTile, which needs a Material
      // ancestor to paint its background + ink splash. The outermost
      // surface uses Material directly (instead of Container + BoxDecoration)
      // so the ListTile finds Material as its nearest ancestor — fixes
      // the debug-only "ListTile background color or ink splashes may be
      // invisible" assertion.
      child: Material(
        color: palette.surfaceWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
          side: BorderSide(color: palette.border),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          title: Text(
            'More',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          subtitle: Text(
            'Hours, stats, and pending actions',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.steel,
                ),
          ),
          children: children,
        ),
      ),
    );
  }
}

// ─── Greeting Header ──────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({this.email});

  final String? email;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _dateLabel {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;
    final name = email?.split('@').first ?? 'worker';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting, $name',
          style: textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _dateLabel,
          style: textTheme.bodyMedium?.copyWith(color: palette.steel),
        ),
      ],
    );
  }
}

// ─── Worker Hours Section ─────────────────────────────────────

class _WorkerHoursSection extends StatelessWidget {
  const _WorkerHoursSection({required this.state});

  final AsyncValue<WorkerHoursSnapshot> state;

  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (summary) => WorkerHoursSummary(
        hoursToday: summary.hoursToday,
        hoursThisWeek: summary.hoursThisWeek,
        hoursThisMonth: summary.hoursThisMonth,
      ),
      loading: () => const _WorkerHoursStatusCard(message: 'Syncing'),
      error: (error, _) =>
          const _WorkerHoursStatusCard(message: 'Unavailable', isError: true),
    );
  }
}

class _WorkerHoursStatusCard extends StatelessWidget {
  const _WorkerHoursStatusCard({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labelColor = isError ? palette.danger : palette.signal;
    return Stack(
      children: [
        const WorkerHoursSummary(),
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: labelColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Active Job Card ──────────────────────────────────────────

class _ActiveJobCard extends StatelessWidget {
  const _ActiveJobCard({
    required this.jobName,
    required this.clockedInAt,
    required this.palette,
    required this.textTheme,
  });

  final String jobName;
  final DateTime? clockedInAt;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  String _elapsed() {
    if (clockedInAt == null) return '';
    final d = DateTime.now().toUtc().difference(clockedInAt!);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m elapsed';
    return '${h}h ${m}m elapsed';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.success.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.work_rounded, color: palette.success, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active: $jobName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (clockedInAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _elapsed(),
                    style: textTheme.bodySmall?.copyWith(color: palette.steel),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.circle, color: palette.success, size: 10),
        ],
      ),
    );
  }
}

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_attendance_repository.dart';
import 'package:fieldops_mobile/features/foreman/presentation/crew_attendance_controller.dart';
import 'package:fieldops_mobile/features/foreman/presentation/crew_clock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Foreman screen for clocking in/out crew members on their behalf.
/// Shows list of crew with their current status and clock action buttons.
class CrewClockScreen extends ConsumerWidget {
  const CrewClockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceState = ref.watch(crewAttendanceProvider);
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crew Clock-In'),
        leading: const BackButton(),
      ),
      body: attendanceState.when(
        data: (crew) {
          if (crew.isEmpty) {
            return _EmptyState(palette: palette, textTheme: textTheme);
          }

          // Group by status
          final clockedIn =
              crew.where((c) => c.status == CrewClockStatus.clockedIn).toList();
          final onBreak =
              crew.where((c) => c.status == CrewClockStatus.onBreak).toList();
          final late =
              crew.where((c) => c.status == CrewClockStatus.late_).toList();
          final absent =
              crew.where((c) => c.status == CrewClockStatus.absent).toList();

          return RefreshIndicator(
            onRefresh: () => ref.read(crewAttendanceProvider.notifier).reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                // Instructions card
                _InstructionsCard(palette: palette, textTheme: textTheme),
                const SizedBox(height: 20),

                // Clock out section first (needs attention)
                if (clockedIn.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Clock Out',
                    count: clockedIn.length,
                    color: palette.success,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...clockedIn.map((m) => _CrewClockTile(
                        member: m,
                        action: CrewClockAction.clockOut,
                      )),
                  const SizedBox(height: 20),
                ],

                // On break section
                if (onBreak.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'On Break',
                    count: onBreak.length,
                    color: const Color(0xFF2563EB),
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...onBreak.map((m) => _CrewClockTile(
                        member: m,
                        action: CrewClockAction.clockOut, // Can end break/clock out
                      )),
                  const SizedBox(height: 20),
                ],

                // Late section
                if (late.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Late',
                    count: late.length,
                    color: palette.signal,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...late.map((m) => _CrewClockTile(
                        member: m,
                        action: CrewClockAction.clockIn,
                      )),
                  const SizedBox(height: 20),
                ],

                // Absent section (can clock in)
                if (absent.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Not Clocked In',
                    count: absent.length,
                    color: palette.danger,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...absent.map((m) => _CrewClockTile(
                        member: m,
                        action: CrewClockAction.clockIn,
                      )),
                ],
              ],
            ),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonLoader(itemCount: 6),
        ),
        error: (error, _) {
          final message = error is CrewAttendanceException
              ? error.message
              : 'Could not load crew.';
          return _ErrorState(message: message, textTheme: textTheme);
        },
      ),
    );
  }
}

enum CrewClockAction { clockIn, clockOut }

class _CrewClockTile extends ConsumerWidget {
  const _CrewClockTile({
    required this.member,
    required this.action,
  });

  final CrewMemberStatus member;
  final CrewClockAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = _statusColor(member.status, palette);

    // Watch this specific member's clock state
    final clockState = ref.watch(crewClockControllerProvider(member.workerId));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: statusColor.withValues(alpha: 0.12),
            child: Text(
              _initials(member.workerName),
              style: textTheme.labelLarge?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name + Job
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.workerName, style: textTheme.titleSmall),
                if (member.jobName != null)
                  Text(
                    member.jobName!,
                    style: textTheme.bodySmall?.copyWith(color: palette.steel),
                  ),
              ],
            ),
          ),

          // Clock action button
          clockState.when(
            data: (_) => _ActionButton(
              action: action,
              onTap: () => _handleClockAction(context, ref),
            ),
            loading: () => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (error, _) => Tooltip(
              message: error.toString(),
              child: Icon(Icons.error_outline, color: palette.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleClockAction(BuildContext context, WidgetRef ref) async {
    final palette = Theme.of(context).extension<FieldOpsPalette>()!;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == CrewClockAction.clockIn ? 'Clock In' : 'Clock Out'),
        content: Text(
          '${action == CrewClockAction.clockIn ? 'Clock in' : 'Clock out'} ${member.workerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action == CrewClockAction.clockIn ? 'Clock In' : 'Clock Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Show job selector if needed
    final selectedJobId = member.jobName != null
        // ignore: use_build_context_synchronously
        ? await _showJobSelector(context, ref)
        // ignore: use_build_context_synchronously
        : await _showAllJobsSelector(context, ref);

    if (selectedJobId == null) return;

    // Perform clock action
    final notifier =
        ref.read(crewClockControllerProvider(member.workerId).notifier);

    try {
      if (action == CrewClockAction.clockIn) {
        await notifier.clockIn(
          workerId: member.workerId,
          jobId: selectedJobId,
        );
      } else {
        await notifier.clockOut(
          workerId: member.workerId,
          jobId: selectedJobId,
        );
      }

      // Refresh attendance
      ref.invalidate(crewAttendanceProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${member.workerName} ${action == CrewClockAction.clockIn ? 'clocked in' : 'clocked out'}',
            ),
            backgroundColor: palette.success,
          ),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: palette.danger,
          ),
        );
      }
    }
  }

  Future<String?> _showJobSelector(BuildContext context, WidgetRef ref) async {
    // Return current job if available
    return null; // Placeholder - would fetch from repository
  }

  Future<String?> _showAllJobsSelector(BuildContext context, WidgetRef ref) async {
    // Show job picker dialog
    return null; // Placeholder
  }

  Color _statusColor(CrewClockStatus status, FieldOpsPalette palette) {
    return switch (status) {
      CrewClockStatus.clockedIn => palette.success,
      CrewClockStatus.onBreak => const Color(0xFF2563EB),
      CrewClockStatus.late_ => palette.signal,
      CrewClockStatus.absent => palette.danger,
    };
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.onTap,
  });

  final CrewClockAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isClockIn = action == CrewClockAction.clockIn;

    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(isClockIn ? Icons.login : Icons.logout, size: 18),
      label: Text(isClockIn ? 'Clock In' : 'Clock Out'),
      style: FilledButton.styleFrom(
        backgroundColor: isClockIn ? palette.success : palette.signal,
        foregroundColor: Colors.white,
        minimumSize: const Size(100, 36),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.textTheme,
  });

  final String title;
  final int count;
  final Color color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: textTheme.titleMedium),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(FieldOpsRadius.full),
          ),
          child: Text(
            count.toString(),
            style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({
    required this.palette,
    required this.textTheme,
  });

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Icon(Icons.info_outline, color: palette.signal, size: 20),
              const SizedBox(width: 8),
              Text(
                'Foreman Clock-In',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Clock crew members in or out on their behalf. '
            'Uses your device GPS location. Creates audit trail showing who was clocked by whom.',
            style: textTheme.bodySmall?.copyWith(color: palette.steel),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.textTheme,
  });

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.groups_rounded,
            size: 48,
            color: palette.steel.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text('No crew members', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'No crew members are assigned to you today.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: palette.steel),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.textTheme,
  });

  final String message;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: Colors.black.withValues(alpha: 0.32),
          ),
          const SizedBox(height: 12),
          Text('Unable to load crew', style: textTheme.titleLarge),
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

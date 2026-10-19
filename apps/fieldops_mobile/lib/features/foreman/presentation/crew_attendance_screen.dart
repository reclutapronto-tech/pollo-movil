import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_attendance_repository.dart';
import 'package:fieldops_mobile/features/foreman/presentation/crew_attendance_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CrewAttendanceScreen extends ConsumerWidget {
  const CrewAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(crewAttendanceProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crew Attendance'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(crewAttendanceProvider.notifier).reload(),
        child: state.when(
          data: (crew) {
            if (crew.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 120),
                  _EmptyState(palette: palette, textTheme: textTheme),
                ],
              );
            }

            // Group by status for quick scanning
            final clockedIn =
                crew.where((c) => c.status == CrewClockStatus.clockedIn).toList();
            final onBreak =
                crew.where((c) => c.status == CrewClockStatus.onBreak).toList();
            final late_ =
                crew.where((c) => c.status == CrewClockStatus.late_).toList();
            final absent =
                crew.where((c) => c.status == CrewClockStatus.absent).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                // Summary row
                _SummaryRow(
                  total: crew.length,
                  clockedIn: clockedIn.length,
                  onBreak: onBreak.length,
                  late_: late_.length,
                  absent: absent.length,
                  palette: palette,
                  textTheme: textTheme,
                ),
                const SizedBox(height: 20),

                if (late_.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Late',
                    count: late_.length,
                    color: palette.signal,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...late_.map((m) => _CrewMemberTile(member: m)),
                  const SizedBox(height: 16),
                ],

                if (clockedIn.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Clocked In',
                    count: clockedIn.length,
                    color: palette.success,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...clockedIn.map((m) => _CrewMemberTile(member: m)),
                  const SizedBox(height: 16),
                ],

                if (onBreak.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'On Break',
                    count: onBreak.length,
                    color: const Color(0xFF2563EB),
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...onBreak.map((m) => _CrewMemberTile(member: m)),
                  const SizedBox(height: 16),
                ],

                if (absent.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Absent',
                    count: absent.length,
                    color: palette.danger,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 8),
                  ...absent.map((m) => _CrewMemberTile(member: m)),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 6),
          ),
          error: (error, _) {
            final message = error is CrewAttendanceException
                ? error.message
                : 'Could not load crew attendance.';
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
}

// ─── Summary Row ──────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total,
    required this.clockedIn,
    required this.onBreak,
    required this.late_,
    required this.absent,
    required this.palette,
    required this.textTheme,
  });

  final int total;
  final int clockedIn;
  final int onBreak;
  final int late_;
  final int absent;
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
          Text('Today\'s Crew', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountChip(
                count: clockedIn,
                label: 'Active',
                color: palette.success,
                textTheme: textTheme,
              ),
              const SizedBox(width: 8),
              _CountChip(
                count: onBreak,
                label: 'Break',
                color: const Color(0xFF2563EB),
                textTheme: textTheme,
              ),
              const SizedBox(width: 8),
              _CountChip(
                count: late_,
                label: 'Late',
                color: palette.signal,
                textTheme: textTheme,
              ),
              const SizedBox(width: 8),
              _CountChip(
                count: absent,
                label: 'Absent',
                color: palette.danger,
                textTheme: textTheme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.color,
    required this.textTheme,
  });

  final int count;
  final String label;
  final Color color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────

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

// ─── Crew Member Tile ─────────────────────────────────────────

class _CrewMemberTile extends StatelessWidget {
  const _CrewMemberTile({required this.member});

  final CrewMemberStatus member;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = _statusColor(member.status, palette);

    final elapsedStr = member.clockedInAt != null
        ? _formatElapsed(DateTime.now().difference(member.clockedInAt!))
        : null;

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
          // Avatar placeholder
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

          // Name + detail
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.workerName, style: textTheme.titleSmall),
                if (member.jobName != null || elapsedStr != null)
                  Text(
                    [
                      if (member.jobName != null) member.jobName!,
                      if (elapsedStr != null) elapsedStr,
                    ].join(' \u00B7 '),
                    style: textTheme.bodySmall?.copyWith(color: palette.steel),
                  ),
              ],
            ),
          ),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(FieldOpsRadius.full),
            ),
            child: Text(
              member.status.label,
              style: textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
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

  String _formatElapsed(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
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
        Text('Attendance unavailable', style: textTheme.titleLarge),
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

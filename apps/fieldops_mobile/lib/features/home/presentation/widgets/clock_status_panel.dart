import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ClockStatusPanel extends StatelessWidget {
  const ClockStatusPanel({
    super.key,
    required this.state,
    this.onClockOut,
    this.onBreakToggle,
  });

  final ClockState state;
  final VoidCallback? onClockOut;
  final VoidCallback? onBreakToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final isClockedIn = state.isClockedIn;
    final isClockingOut = state.activeRequestJobId != null && isClockedIn;
    final title = state.isOnBreak
        ? 'On break'
        : isClockedIn
            ? 'Clocked in'
            : 'Ready to clock in';
    final subtitle = state.isOnBreak
        ? 'Break active for ${state.activeJobName}. Tap End Break to resume.'
        : isClockedIn
            ? 'Active job: ${state.activeJobName}'
            : state.lastCompletedJobName != null
                ? 'Clocked out of ${state.lastCompletedJobName}. Choose a job to start again.'
                : 'Choose an assigned job below to begin your shift.';

    return Semantics(
      label: '$title. $subtitle',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isClockedIn
                ? [palette.success.withValues(alpha: 0.18), palette.surfaceWhite]
                : [palette.signal.withValues(alpha: 0.16), palette.surfaceWhite],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isClockedIn
                ? palette.success.withValues(alpha: 0.35)
                : palette.border,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surfaceWhite,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    isClockedIn
                        ? Icons.verified_user_rounded
                        : Icons.timelapse_rounded,
                    color: isClockedIn ? palette.success : palette.signal,
                    semanticLabel: isClockedIn
                        ? 'Verified clock status'
                        : 'Pending clock-in',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(subtitle, style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (isClockedIn && onClockOut != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Clock out of ${state.activeJobName}',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.danger,
                          side: BorderSide(
                            color: palette.danger.withValues(alpha: 0.4),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: isClockingOut
                            ? null
                            : () {
                                HapticFeedback.heavyImpact();
                                onClockOut?.call();
                              },
                        icon: isClockingOut
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.danger,
                                ),
                              )
                            : const Icon(Icons.stop_circle_outlined),
                        label: Text(
                          isClockingOut ? 'Clocking out...' : 'Clock out',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Request overtime for ${state.activeJobName}',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.signal,
                          side: BorderSide(
                            color: palette.signal.withValues(alpha: 0.4),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: state.activeJobId == null
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                Navigator.of(context).push(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => OTRequestScreen(
                                      jobId: state.activeJobId!,
                                      jobName: state.activeJobName ?? '',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.more_time_rounded),
                        label: const Text('Request OT'),
                      ),
                    ),
                  ),
                ],
              ),
              if (onBreakToggle != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: Semantics(
                    button: true,
                    label: state.isOnBreak ? 'End break' : 'Start break',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            state.isOnBreak ? palette.success : palette.steel,
                        side: BorderSide(
                          color: state.isOnBreak
                              ? palette.success.withValues(alpha: 0.4)
                              : palette.steel.withValues(alpha: 0.3),
                        ),
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        onBreakToggle?.call();
                      },
                      icon: Icon(
                        state.isOnBreak
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      label: Text(
                        state.isOnBreak ? 'End Break' : 'Start Break',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

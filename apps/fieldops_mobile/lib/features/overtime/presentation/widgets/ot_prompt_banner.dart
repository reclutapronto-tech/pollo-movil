import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_auto_detector.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OTPromptBanner extends ConsumerWidget {
  const OTPromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otState = ref.watch(otAutoDetectorProvider);
    final clockState = ref.watch(clockControllerProvider);

    if (!otState.shouldShowPrompt || !clockState.isClockedIn) {
      return const SizedBox.shrink();
    }

    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final hours = otState.currentHours.toStringAsFixed(1);

    return Semantics(
      liveRegion: true,
      label: 'Overtime alert. You have worked $hours hours.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.signal.withValues(alpha: 0.15),
              palette.danger.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
          border: Border.all(color: palette.signal.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: palette.signal, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are entering overtime',
                    style: textTheme.titleLarge
                        ?.copyWith(color: palette.signal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You have worked $hours hours on ${clockState.activeJobName}. '
              'Submit an OT verification to continue working.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) => OTRequestScreen(
                            jobId: clockState.activeJobId!,
                            jobName: clockState.activeJobName!,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.more_time_rounded),
                    label: const Text('Submit OT Request'),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () =>
                      ref.read(otAutoDetectorProvider.notifier).dismissPrompt(),
                  child: Text(
                    'Dismiss',
                    style: textTheme.labelMedium
                        ?.copyWith(color: palette.steel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

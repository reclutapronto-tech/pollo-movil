import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/core/data/pending_count_provider.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_auto_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aggregated pending actions card.
///
/// Shows actionable items the worker should address: unsent photos,
/// pending OT, queued sync events. Collapses to nothing when all clear.
class PendingActionsCard extends ConsumerWidget {
  const PendingActionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final pendingAsync = ref.watch(pendingEventCountProvider);
    final photoDraftsAsync = ref.watch(pendingPhotoDraftCountProvider);
    final otState = ref.watch(otAutoDetectorProvider);
    final clockState = ref.watch(clockControllerProvider);

    final pendingCount = pendingAsync.value ?? 0;
    final draftCount = photoDraftsAsync.value ?? 0;
    final hasOTPrompt = otState.shouldShowPrompt && clockState.isClockedIn;

    final actions = <_PendingAction>[];

    if (draftCount > 0) {
      actions.add(_PendingAction(
        icon: Icons.photo_library_outlined,
        label: '$draftCount photo${draftCount == 1 ? '' : 's'} saved locally',
        color: palette.signal,
      ));
    }

    if (hasOTPrompt) {
      actions.add(_PendingAction(
        icon: Icons.more_time_rounded,
        label: 'OT request needed',
        color: palette.danger,
      ));
    }

    if (pendingCount > 0) {
      actions.add(_PendingAction(
        icon: Icons.sync_rounded,
        label: '$pendingCount event${pendingCount == 1 ? '' : 's'} queued to sync',
        color: palette.signal,
      ));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.signal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.signal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  size: 18, color: palette.signal),
              const SizedBox(width: 8),
              Text(
                'Pending Actions',
                style: textTheme.titleMedium?.copyWith(
                  color: palette.signal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...actions.map((action) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: action.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(action.icon, size: 16, color: action.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        action.label,
                        style: textTheme.bodyMedium?.copyWith(
                          color: palette.slate,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _PendingAction {
  const _PendingAction({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;
}

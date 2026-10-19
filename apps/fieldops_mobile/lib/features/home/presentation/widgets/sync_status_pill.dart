import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/core/data/connectivity_provider.dart';
import 'package:fieldops_mobile/core/data/pending_count_provider.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/home/presentation/widgets/pending_actions_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persistent sync-state chip for the app bar.
///
/// Shows at a glance whether the device is connected and whether local
/// work is still queued. Tapping opens a sheet with the full pending
/// actions list so the worker can see exactly what's outstanding.
class SyncStatusPill extends ConsumerWidget {
  const SyncStatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final pendingCount = ref.watch(pendingEventCountProvider).value ?? 0;
    final draftCount = ref.watch(pendingPhotoDraftCountProvider).value ?? 0;
    final palette = context.palette;

    final totalQueued = pendingCount + draftCount;

    final Color color;
    final IconData icon;
    final String label;
    final String semantic;

    if (!isOnline) {
      color = palette.danger;
      icon = Icons.cloud_off_rounded;
      label = totalQueued > 0 ? 'Offline · $totalQueued' : 'Offline';
      semantic = totalQueued > 0
          ? 'Offline, $totalQueued item${totalQueued == 1 ? '' : 's'} queued'
          : 'Offline';
    } else if (totalQueued > 0) {
      color = palette.signal;
      icon = Icons.sync_rounded;
      label = '$totalQueued queued';
      semantic =
          '$totalQueued item${totalQueued == 1 ? '' : 's'} queued, syncing';
    } else {
      color = palette.success;
      icon = Icons.check_circle_rounded;
      label = 'Synced';
      semantic = 'All changes synced';
    }

    return Semantics(
      button: true,
      label: semantic,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () => _showPendingSheet(context),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPendingSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sync status',
                  style: Theme.of(sheetCtx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const PendingActionsCard(),
              ],
            ),
          ),
        );
      },
    );
  }
}

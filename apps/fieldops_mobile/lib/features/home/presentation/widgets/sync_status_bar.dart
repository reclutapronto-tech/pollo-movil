import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/core/data/connectivity_provider.dart';
import 'package:fieldops_mobile/core/data/pending_count_provider.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final pendingAsync = ref.watch(pendingEventCountProvider);
    final photoDraftsAsync = ref.watch(pendingPhotoDraftCountProvider);
    final count = pendingAsync.value ?? 0;
    final draftCount = photoDraftsAsync.value ?? 0;

    if (isOnline && count == 0 && draftCount == 0) {
      return const SizedBox.shrink();
    }

    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final Color color;
    final IconData icon;
    final String label;

    if (!isOnline) {
      color = palette.danger;
      icon = Icons.cloud_off_rounded;
      if (count > 0 || draftCount > 0) {
        final parts = <String>[];
        if (count > 0) {
          parts.add('$count event${count == 1 ? '' : 's'} queued');
        }
        if (draftCount > 0) {
          parts.add('$draftCount photo${draftCount == 1 ? '' : 's'} saved');
        }
        label = 'Offline — ${parts.join(' • ')}';
      } else {
        label = 'Offline — events will queue locally';
      }
    } else {
      color = palette.signal;
      icon = draftCount > 0 ? Icons.photo_library_outlined : Icons.sync_rounded;
      if (count > 0 && draftCount > 0) {
        label =
            '$count event${count == 1 ? '' : 's'} syncing • $draftCount saved photo${draftCount == 1 ? '' : 's'} waiting';
      } else if (count > 0) {
        label = '$count event${count == 1 ? '' : 's'} syncing...';
      } else {
        label =
            '$draftCount saved photo${draftCount == 1 ? '' : 's'} waiting to send';
      }
    }

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border(
            bottom: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

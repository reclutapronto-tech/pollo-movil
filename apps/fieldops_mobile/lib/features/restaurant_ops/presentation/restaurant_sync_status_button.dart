import 'package:fieldops_mobile/core/data/connectivity_provider.dart';
import 'package:fieldops_mobile/core/data/pending_count_provider.dart';
import 'package:fieldops_mobile/core/data/sync_engine.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantSyncStatusButton extends ConsumerWidget {
  const RestaurantSyncStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final online = ref.watch(isOnlineProvider);
    final pending = ref.watch(pendingEventCountProvider).value ?? 0;
    final attention = ref
        .watch(outboxAttentionEventsProvider)
        .maybeWhen(data: (events) => events.length, orElse: () => 0);
    final total = pending + attention;
    final color = !online
        ? Theme.of(context).colorScheme.error
        : attention > 0
        ? Theme.of(context).colorScheme.error
        : total > 0
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.primary;
    final label = !online
        ? total > 0
              ? l10n.restaurantSyncOfflinePending(total)
              : l10n.restaurantSyncOffline
        : attention > 0
        ? l10n.restaurantSyncAttentionCount(attention)
        : total > 0
        ? l10n.restaurantSyncPendingCount(pending)
        : l10n.restaurantSyncAllDone;

    return IconButton(
      tooltip: l10n.restaurantSyncTooltip(label),
      onPressed: () async {
        try {
          await ref.read(syncEngineProvider).syncPendingEvents();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  online
                      ? l10n.restaurantSyncStarted
                      : l10n.restaurantSyncOfflineSaved,
                ),
              ),
            );
          }
        } on Object {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.restaurantSyncFailure)));
          }
        }
      },
      icon: Badge(
        isLabelVisible: total > 0,
        label: Text(total > 99 ? '99+' : '$total'),
        child: Icon(
          !online
              ? Icons.cloud_off_rounded
              : attention > 0
              ? Icons.sync_problem_rounded
              : total > 0
              ? Icons.sync_rounded
              : Icons.cloud_done_outlined,
          color: color,
        ),
      ),
    );
  }
}

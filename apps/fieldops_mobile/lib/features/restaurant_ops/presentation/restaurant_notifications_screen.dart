import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RestaurantNotificationsScreen extends ConsumerWidget {
  const RestaurantNotificationsScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.onOpenNotification,
  });

  final String branchId;
  final String branchName;
  final ValueChanged<Map<String, dynamic>> onOpenNotification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(branchId), (
      previous,
      next,
    ) {
      if (next.hasValue) {
        ref.invalidate(restaurantNotificationsProvider(branchId));
      }
    });
    final inbox = ref.watch(restaurantNotificationsProvider(branchId));
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final pendingEvents = ref
        .watch(restaurantOutboxEventsProvider(branchId))
        .maybeWhen(data: (events) => events, orElse: () => const <PendingEvent>[]);
    final displayedInbox = userId == null
        ? inbox
        : inbox.whenData(
            (data) => projectPendingRestaurantNotificationReads(
              inbox: data,
              events: pendingEvents,
              branchId: branchId,
              actorId: userId,
            ),
          );

    Future<void> markRead(Map<String, dynamic> item) async {
      if (item['read_at'] != null || item['_pending_read'] == true) return;
      try {
        final result = await ref
            .read(restaurantOpsRepositoryProvider)
            .markNotificationRead(
              branchId: branchId,
              notificationId: item['id'] as String,
            );
        ref.invalidate(restaurantNotificationsProvider(branchId));
        if (context.mounted && result['queued'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.restaurantNotificationsQueuedRead)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }

    Future<void> openNotification(Map<String, dynamic> item) async {
      await markRead(item);
      if (context.mounted) onOpenNotification(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.restaurantNotificationsTitle),
            Text(branchName, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          displayedInbox.maybeWhen(
            data: (data) => (data['unread_count'] as num? ?? 0) > 0
                ? TextButton(
                    onPressed: () async {
                      try {
                        final result = await ref
                            .read(restaurantOpsRepositoryProvider)
                            .markAllNotificationsRead(branchId);
                        ref.invalidate(
                          restaurantNotificationsProvider(branchId),
                        );
                        if (context.mounted && result['queued'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                l10n.restaurantNotificationsQueuedRead,
                              ),
                            ),
                          );
                        }
                      } on Object catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
                    child: Text(l10n.restaurantNotificationsMarkAllRead),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: displayedInbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _InboxMessage(
          message: l10n.restaurantNotificationsLoadError(error.toString()),
          onRetry: () =>
              ref.invalidate(restaurantNotificationsProvider(branchId)),
        ),
        data: (data) {
          final items = (data['notifications'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final offlineSnapshot = data['_offline_snapshot'] == true;
          if (items.isEmpty) {
            return _InboxMessage(
              message: offlineSnapshot
                  ? l10n.restaurantNotificationsOfflineEmpty
                  : l10n.restaurantNotificationsEmpty,
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(restaurantNotificationsProvider(branchId)),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length + (offlineSnapshot ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (offlineSnapshot && index == 0) {
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.cloud_off_rounded),
                      title: Text(l10n.restaurantNotificationsOfflineTitle),
                      subtitle: Text(l10n.restaurantNotificationsOfflineBody),
                    ),
                  );
                }
                final item = items[index - (offlineSnapshot ? 1 : 0)];
                final pendingRead = item['_pending_read'] == true;
                final isUnread = item['read_at'] == null && !pendingRead;
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: () => openNotification(item),
                    leading: CircleAvatar(
                      backgroundColor: isUnread
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        _iconFor(item['notification_type'] as String?),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item['title'] as String? ??
                          l10n.restaurantNotificationFallbackTitle,
                      style: TextStyle(
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['body'] as String? ?? ''),
                          const SizedBox(height: 5),
                          Text(
                            _timeLabel(context, item['created_at'] as String?),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    trailing: pendingRead
                        ? Tooltip(
                            message: l10n.restaurantNotificationReadPending,
                            child: Icon(Icons.cloud_upload_outlined),
                          )
                        : isUnread
                        ? IconButton(
                            tooltip: l10n.restaurantNotificationMarkRead,
                            icon: const Icon(Icons.mark_email_read_outlined),
                            onPressed: () => markRead(item),
                          )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(String? type) => switch (type) {
    'incident_assigned' || 'incident_reported' => Icons.report_outlined,
    'shift_handoff_received' ||
    'shift_handoff_acknowledged' => Icons.swap_horiz_rounded,
    'shift_published' ||
    'shift_updated' ||
    'shift_removed' => Icons.schedule_rounded,
    'absence_requested' || 'absence_reviewed' => Icons.event_note_outlined,
    'inspection_attention' => Icons.fact_check_outlined,
    'task_part_assigned' => Icons.grid_view_rounded,
    _ => Icons.assignment_outlined,
  };

  String _timeLabel(BuildContext context, String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';
    final formattedDate = MaterialLocalizations.of(
      context,
    ).formatMediumDate(date);
    final formattedTime = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(date));
    return '$formattedDate · $formattedTime';
  }
}

class _InboxMessage extends StatelessWidget {
  const _InboxMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context)!.retry),
            ),
          ],
        ],
      ),
    ),
  );
}

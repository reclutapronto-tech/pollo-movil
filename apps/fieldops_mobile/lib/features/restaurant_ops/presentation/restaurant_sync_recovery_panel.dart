import 'dart:convert';

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/core/data/pending_count_provider.dart';
import 'package:fieldops_mobile/core/data/sync_engine.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantSyncRecoveryPanel extends ConsumerStatefulWidget {
  const RestaurantSyncRecoveryPanel({super.key});

  @override
  ConsumerState<RestaurantSyncRecoveryPanel> createState() =>
      _RestaurantSyncRecoveryPanelState();
}

class _RestaurantSyncRecoveryPanelState
    extends ConsumerState<RestaurantSyncRecoveryPanel> {
  String? _retryingId;

  Future<void> _retry(PendingEvent event) async {
    if (_retryingId != null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _retryingId = event.id);
    try {
      await ref.read(localDatabaseProvider).retryFailedEvent(event.id);
      await ref.read(syncEngineProvider).syncPendingEvents();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.restaurantSyncRetryQueued)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.restaurantSyncRetryFailed)));
      }
    } finally {
      if (mounted) setState(() => _retryingId = null);
    }
  }

  String _eventLabel(PendingEvent event, AppLocalizations l10n) {
    if (event.eventType == 'restaurant_ops') {
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['action'] == 'record_time_event') {
          return l10n.restaurantSyncEventClock;
        }
      } on FormatException {
        // Keep malformed payload details private and use the generic label.
      }
    }
    return switch (event.eventType) {
      'restaurant_ops' => l10n.restaurantSyncEventOperations,
      'clock_event' => l10n.restaurantSyncEventClockEvent,
      'photo_presign' || 'photo_finalize' => l10n.restaurantSyncEventEvidence,
      _ => l10n.restaurantSyncEventPending,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final attention = ref
        .watch(outboxAttentionEventsProvider)
        .maybeWhen(
          data: (events) => events,
          orElse: () => const <PendingEvent>[],
        );
    if (attention.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_problem_rounded, color: palette.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.restaurantSyncAttentionNotice(attention.length),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.restaurantSyncAttentionHelp),
          const SizedBox(height: 8),
          ...attention.map((event) {
            final localTime = event.occurredAt.toLocal();
            final when =
                '${MaterialLocalizations.of(context).formatShortDate(localTime)} · '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_eventLabel(event, l10n)),
              subtitle: Text(when),
              trailing: event.syncStatus == 'waiting_account'
                  ? Icon(
                      Icons.person_outline_rounded,
                      semanticLabel: l10n.restaurantSyncRequiresOriginalAccount,
                    )
                  : TextButton.icon(
                      onPressed: _retryingId == null
                          ? () => _retry(event)
                          : null,
                      icon: _retryingId == event.id
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.restaurantSyncRetry),
                    ),
            );
          }),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:fieldops_mobile/app/main_shell.dart'
    show activeTabKeyProvider, mainShellNavigatorKey;
import 'package:fieldops_mobile/core/notifications/notification_service.dart'
    show PushNotification, notificationServiceProvider;
import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart'
    show restaurantBranchesProvider, restaurantSelectedBranchProvider;
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Routes incoming push notifications to the correct app screen.
///
/// Attach to the widget tree via [NotificationListener] widget or
/// call [startListening] from a top-level consumer.
class NotificationHandler {
  NotificationHandler(this._ref);

  final Ref _ref;
  StreamSubscription<PushNotification>? _foregroundSubscription;
  StreamSubscription<PushNotification>? _openedSubscription;

  /// Begin listening for foreground notifications.
  void startListening() {
    if (_foregroundSubscription != null || _openedSubscription != null) return;
    final service = _ref.read(notificationServiceProvider);
    _foregroundSubscription = service.onForegroundMessage.listen(_onMessage);
    _openedSubscription = service.onNotificationOpened.listen((notification) {
      unawaited(_navigateToTab(notification));
    });
  }

  /// Stop listening (call in dispose / onDispose).
  void stopListening() {
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    _foregroundSubscription = null;
    _openedSubscription = null;
  }

  /// Handle a notification that was tapped (from terminated or background).
  Future<void> handleInitialMessage() async {
    final service = _ref.read(notificationServiceProvider);
    final initial = await service.getInitialMessage();
    if (initial != null) {
      await _navigateToTab(initial);
    }
  }

  void _onMessage(PushNotification notification) {
    final context = mainShellNavigatorKey.currentContext;
    if (context == null) return;
    final targetTab = _targetTab(notification);

    // Show in-app banner for foreground notifications.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (notification.body.isNotEmpty) Text(notification.body),
          ],
        ),
        action: targetTab != null
            ? SnackBarAction(
                label: AppLocalizations.of(context)!.restaurantNotificationView,
                onPressed: () => unawaited(_navigateToTab(notification)),
              )
            : null,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _navigateToTab(PushNotification notification) async {
    final tab = _targetTab(notification);
    if (tab != null) {
      _ref.read(activeTabKeyProvider.notifier).setTab(tab);
    }

    final requestedBranchId = notification.data['branch_id']?.toString();
    if (requestedBranchId != null && requestedBranchId.isNotEmpty) {
      try {
        final branches = await _ref.read(restaurantBranchesProvider.future);
        final branchIsAccessible = branches.any(
          (branch) => branch['id'] == requestedBranchId,
        );
        if (branchIsAccessible) {
          _ref
              .read(restaurantSelectedBranchProvider.notifier)
              .selectBranch(requestedBranchId);
        }
      } on Object {
        // Keep notification navigation available if branch refresh is offline.
      }
    }
  }

  String? _targetTab(PushNotification notification) {
    const tabs = {'shift', 'waste', 'incidents', 'handoff', 'clock', 'more'};
    final requested = notification.data['tab']?.toString() ??
        notification.data['route']?.toString();
    if (tabs.contains(requested)) return requested;

    final type = notification.data['notification_type']?.toString() ??
        notification.data['category']?.toString();
    return switch (type) {
      'waste_task_assigned' || 'waste_inspection_due' || 'inspection_due' =>
        'waste',
      'inspection_attention' => 'waste',
      'incident_assigned' || 'incident_reported' || 'incident_updated' =>
        'incidents',
      'handoff_received' || 'shift_handoff_received' => 'handoff',
      'shift_handoff_acknowledged' => 'handoff',
      'shift_published' || 'shift_removed' || 'shift_updated' ||
          'task_assigned' || 'task_part_assigned' || 'absence_requested' ||
          'absence_reviewed' =>
        'shift',
      _ => null,
    };
  }
}

/// Riverpod provider for the notification handler.
final notificationHandlerProvider = Provider<NotificationHandler>((ref) {
  final handler = NotificationHandler(ref);
  ref.onDispose(handler.stopListening);
  return handler;
});

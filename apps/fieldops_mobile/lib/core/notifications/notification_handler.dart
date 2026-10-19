import 'dart:async';

import 'package:fieldops_mobile/core/notifications/notification_service.dart'
    show PushNotification, notificationServiceProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Routes incoming push notifications to the correct app screen.
///
/// Attach to the widget tree via [NotificationListener] widget or
/// call [startListening] from a top-level consumer.
class NotificationHandler {
  NotificationHandler(this._ref);

  final Ref _ref;
  StreamSubscription<PushNotification>? _subscription;

  /// The navigator key used for deep-linking from notifications.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Begin listening for foreground notifications.
  void startListening() {
    final service = _ref.read(notificationServiceProvider);
    _subscription = service.onForegroundMessage.listen(_onMessage);
  }

  /// Stop listening (call in dispose / onDispose).
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Handle a notification that was tapped (from terminated or background).
  Future<void> handleInitialMessage() async {
    final service = _ref.read(notificationServiceProvider);
    final initial = await service.getInitialMessage();
    if (initial != null) {
      _navigateToRoute(initial);
    }
  }

  void _onMessage(PushNotification notification) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

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
        action: notification.route != null
            ? SnackBarAction(
                label: 'View',
                onPressed: () => _navigateToRoute(notification),
              )
            : null,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _navigateToRoute(PushNotification notification) {
    final route = notification.route;
    if (route == null) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // Route map — extend as new notification types are added.
    navigator.pushNamed(route, arguments: notification.data);
  }
}

/// Riverpod provider for the notification handler.
final notificationHandlerProvider = Provider<NotificationHandler>((ref) {
  final handler = NotificationHandler(ref);
  ref.onDispose(handler.stopListening);
  return handler;
});

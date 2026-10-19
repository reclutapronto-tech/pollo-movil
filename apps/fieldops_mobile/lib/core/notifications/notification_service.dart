// Push notification service.
//
// FCM activation requires:
// 1. Firebase project → `flutterfire configure`
// 2. Add to pubspec.yaml: firebase_core, firebase_messaging
// 3. APNs key upload for iOS (Apple Developer portal)
// 4. Uncomment FirebaseNotificationService below
// 5. Switch provider in notification_provider.dart
//
// This file provides the service interface, a no-op stub for development,
// and the ready-to-activate Firebase implementation.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notification payload from a push message.
class PushNotification {
  const PushNotification({
    required this.title,
    required this.body,
    this.data = const {},
  });

  final String title;
  final String body;
  final Map<String, dynamic> data;

  /// Route to navigate to when tapped, derived from [data].
  String? get route => data['route'] as String?;

  /// Entity ID referenced in the notification (e.g. shift, OT request).
  String? get entityId => data['entity_id'] as String?;
}

/// Push notification categories the app handles.
enum NotificationCategory {
  otApproval,
  ptoUpdate,
  schedulePublished,
  shiftSwapResult,
  safetyAlert,
  expenseApproval,
  timecardReady,
  general,
}

/// Parse a notification category string from push data.
NotificationCategory parseNotificationCategory(String? value) {
  switch (value) {
    case 'ot_approval':
      return NotificationCategory.otApproval;
    case 'pto_update':
      return NotificationCategory.ptoUpdate;
    case 'schedule_published':
      return NotificationCategory.schedulePublished;
    case 'shift_swap_result':
      return NotificationCategory.shiftSwapResult;
    case 'safety_alert':
      return NotificationCategory.safetyAlert;
    case 'expense_approval':
      return NotificationCategory.expenseApproval;
    case 'timecard_ready':
      return NotificationCategory.timecardReady;
    default:
      return NotificationCategory.general;
  }
}

/// Notification service interface for push notifications.
abstract class NotificationService {
  /// Initialize the notification subsystem (request permissions, etc.).
  Future<void> initialize();

  /// Returns the device push token, or null if unavailable.
  Future<String?> getDeviceToken();

  /// Register the device token with the backend for targeted push.
  Future<void> registerToken(String token);

  /// Stream of notifications received while the app is in the foreground.
  Stream<PushNotification> get onForegroundMessage;

  /// Returns the notification that launched the app (if any).
  Future<PushNotification?> getInitialMessage();
}

/// Placeholder until Firebase is configured.
class NoOpNotificationService implements NotificationService {
  const NoOpNotificationService();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> getDeviceToken() async => null;

  @override
  Future<void> registerToken(String token) async {}

  @override
  Stream<PushNotification> get onForegroundMessage => const Stream.empty();

  @override
  Future<PushNotification?> getInitialMessage() async => null;
}

// ---------------------------------------------------------------------------
// Firebase implementation — activate when Firebase project is configured.
// ---------------------------------------------------------------------------
//
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
//
// /// Handle background messages (must be top-level function).
// @pragma('vm:entry-point')
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
//   await Firebase.initializeApp();
//   // Background processing (e.g., update badge count, store to local DB).
// }
//
// class FirebaseNotificationService implements NotificationService {
//   FirebaseNotificationService(this._ref);
//
//   final Ref _ref;
//   final _foregroundController = StreamController<PushNotification>.broadcast();
//
//   @override
//   Future<void> initialize() async {
//     await Firebase.initializeApp();
//
//     FirebaseMessaging.onBackgroundMessage(
//       _firebaseMessagingBackgroundHandler,
//     );
//
//     // Request permission (iOS / macOS).
//     final settings = await FirebaseMessaging.instance.requestPermission(
//       alert: true,
//       badge: true,
//       sound: true,
//       provisional: false,
//     );
//
//     if (settings.authorizationStatus == AuthorizationStatus.authorized ||
//         settings.authorizationStatus == AuthorizationStatus.provisional) {
//       // Listen for foreground messages.
//       FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
//
//       // Register token on first launch + token refresh.
//       final token = await FirebaseMessaging.instance.getToken();
//       if (token != null) await registerToken(token);
//
//       FirebaseMessaging.instance.onTokenRefresh.listen(registerToken);
//     }
//   }
//
//   void _handleForegroundMessage(RemoteMessage message) {
//     final notification = PushNotification(
//       title: message.notification?.title ?? '',
//       body: message.notification?.body ?? '',
//       data: message.data,
//     );
//     _foregroundController.add(notification);
//   }
//
//   @override
//   Future<String?> getDeviceToken() async {
//     return FirebaseMessaging.instance.getToken();
//   }
//
//   @override
//   Future<void> registerToken(String token) async {
//     try {
//       final supabase = Supabase.instance.client;
//       await supabase.functions.invoke(
//         'device_tokens',
//         body: {
//           'action': 'register',
//           'token': token,
//           'platform': Platform.isIOS ? 'ios' : 'android',
//         },
//       );
//     } catch (_) {
//       // Token registration is best-effort; don't block app launch.
//     }
//   }
//
//   @override
//   Stream<PushNotification> get onForegroundMessage =>
//       _foregroundController.stream;
//
//   @override
//   Future<PushNotification?> getInitialMessage() async {
//     final msg = await FirebaseMessaging.instance.getInitialMessage();
//     if (msg == null) return null;
//     return PushNotification(
//       title: msg.notification?.title ?? '',
//       body: msg.notification?.body ?? '',
//       data: msg.data,
//     );
//   }
// }

/// Riverpod provider — swap [NoOpNotificationService] for
/// [FirebaseNotificationService] once Firebase is configured.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return const NoOpNotificationService();
});

import 'package:fieldops_mobile/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─── NoOpNotificationService ────────────────────────────────

  group('NoOpNotificationService', () {
    late NoOpNotificationService service;

    setUp(() {
      service = const NoOpNotificationService();
    });

    test('initialize() completes without error', () async {
      await expectLater(service.initialize(), completes);
    });

    test('getDeviceToken() returns null', () async {
      final token = await service.getDeviceToken();
      expect(token, isNull);
    });

    test('registerToken() completes without error', () async {
      await expectLater(service.registerToken('some-token'), completes);
    });

    test('onForegroundMessage returns an empty stream', () async {
      final events = await service.onForegroundMessage.toList();
      expect(events, isEmpty);
    });

    test('getInitialMessage() returns null', () async {
      final msg = await service.getInitialMessage();
      expect(msg, isNull);
    });
  });

  // ─── PushNotification model ─────────────────────────────────

  group('PushNotification', () {
    test('route is extracted from data', () {
      const notification = PushNotification(
        title: 'Schedule Published',
        body: 'Your schedule for next week is ready.',
        data: {'route': '/schedule', 'entity_id': 'shift-42'},
      );

      expect(notification.route, '/schedule');
      expect(notification.entityId, 'shift-42');
    });

    test('route and entityId are null when data is empty', () {
      const notification = PushNotification(
        title: 'General',
        body: 'Hello',
      );

      expect(notification.route, isNull);
      expect(notification.entityId, isNull);
    });

    test('route is null when data does not contain route key', () {
      const notification = PushNotification(
        title: 'OT Approved',
        body: 'Your overtime was approved.',
        data: {'entity_id': 'ot-99'},
      );

      expect(notification.route, isNull);
      expect(notification.entityId, 'ot-99');
    });

    test('entityId is null when data does not contain entity_id key', () {
      const notification = PushNotification(
        title: 'Alert',
        body: 'Safety alert issued.',
        data: {'route': '/safety'},
      );

      expect(notification.route, '/safety');
      expect(notification.entityId, isNull);
    });
  });

  // ─── parseNotificationCategory ──────────────────────────────

  group('parseNotificationCategory', () {
    test('parses ot_approval', () {
      expect(
        parseNotificationCategory('ot_approval'),
        NotificationCategory.otApproval,
      );
    });

    test('parses pto_update', () {
      expect(
        parseNotificationCategory('pto_update'),
        NotificationCategory.ptoUpdate,
      );
    });

    test('parses schedule_published', () {
      expect(
        parseNotificationCategory('schedule_published'),
        NotificationCategory.schedulePublished,
      );
    });

    test('parses shift_swap_result', () {
      expect(
        parseNotificationCategory('shift_swap_result'),
        NotificationCategory.shiftSwapResult,
      );
    });

    test('parses safety_alert', () {
      expect(
        parseNotificationCategory('safety_alert'),
        NotificationCategory.safetyAlert,
      );
    });

    test('parses expense_approval', () {
      expect(
        parseNotificationCategory('expense_approval'),
        NotificationCategory.expenseApproval,
      );
    });

    test('parses timecard_ready', () {
      expect(
        parseNotificationCategory('timecard_ready'),
        NotificationCategory.timecardReady,
      );
    });

    test('returns general for null input', () {
      expect(
        parseNotificationCategory(null),
        NotificationCategory.general,
      );
    });

    test('returns general for unknown string', () {
      expect(
        parseNotificationCategory('something_unknown'),
        NotificationCategory.general,
      );
    });

    test('returns general for empty string', () {
      expect(
        parseNotificationCategory(''),
        NotificationCategory.general,
      );
    });
  });
}

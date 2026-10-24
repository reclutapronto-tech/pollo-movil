import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotification {
  const PushNotification({
    required this.title,
    required this.body,
    this.data = const {},
  });

  final String title;
  final String body;
  final Map<String, dynamic> data;

  String? get route => data['route'] as String?;
  String? get entityId => data['entity_id'] as String?;
}

enum NotificationCategory {
  otApproval,
  ptoUpdate,
  schedulePublished,
  shiftSwapResult,
  safetyAlert,
  expenseApproval,
  timecardReady,
  taskAssigned,
  inspectionDue,
  incidentUpdated,
  handoffReceived,
  general,
}

NotificationCategory parseNotificationCategory(String? value) {
  return switch (value) {
    'ot_approval' => NotificationCategory.otApproval,
    'pto_update' => NotificationCategory.ptoUpdate,
    'schedule_published' || 'shift_published' =>
      NotificationCategory.schedulePublished,
    'shift_swap_result' => NotificationCategory.shiftSwapResult,
    'safety_alert' => NotificationCategory.safetyAlert,
    'expense_approval' => NotificationCategory.expenseApproval,
    'timecard_ready' => NotificationCategory.timecardReady,
    'task_assigned' || 'waste_task_assigned' =>
      NotificationCategory.taskAssigned,
    'inspection_due' || 'waste_inspection_due' =>
      NotificationCategory.inspectionDue,
    'incident_updated' || 'incident_assigned' =>
      NotificationCategory.incidentUpdated,
    'handoff_received' || 'shift_handoff_received' =>
      NotificationCategory.handoffReceived,
    _ => NotificationCategory.general,
  };
}

abstract interface class NotificationService {
  bool get isAvailable;
  Future<bool> get isEnabled;
  Future<void> initialize();
  Future<bool> setEnabled(bool enabled);
  Future<String?> getDeviceToken();
  Future<void> registerToken(String token);
  Future<void> unregisterCurrentDevice();
  Stream<PushNotification> get onForegroundMessage;
  Stream<PushNotification> get onNotificationOpened;
  Future<PushNotification?> getInitialMessage();
}

class NoOpNotificationService implements NotificationService {
  const NoOpNotificationService();

  @override
  bool get isAvailable => false;

  @override
  Future<bool> get isEnabled async => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> setEnabled(bool enabled) async => false;

  @override
  Future<String?> getDeviceToken() async => null;

  @override
  Future<void> registerToken(String token) async {}

  @override
  Future<void> unregisterCurrentDevice() async {}

  @override
  Stream<PushNotification> get onForegroundMessage => const Stream.empty();

  @override
  Stream<PushNotification> get onNotificationOpened => const Stream.empty();

  @override
  Future<PushNotification?> getInitialMessage() async => null;
}

class _FirebaseMobileConfig {
  const _FirebaseMobileConfig({
    required this.apiKey,
    required this.projectId,
    required this.messagingSenderId,
    required this.androidAppId,
    required this.iosAppId,
    required this.iosBundleId,
  });

  factory _FirebaseMobileConfig.fromDartDefines() => const _FirebaseMobileConfig(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
        iosAppId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
        iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
      );

  final String apiKey;
  final String projectId;
  final String messagingSenderId;
  final String androidAppId;
  final String iosAppId;
  final String iosBundleId;

  bool supports(TargetPlatform platform) {
    if (kIsWeb || apiKey.isEmpty || projectId.isEmpty || messagingSenderId.isEmpty) {
      return false;
    }
    return switch (platform) {
      TargetPlatform.android => androidAppId.isNotEmpty,
      TargetPlatform.iOS => iosAppId.isNotEmpty,
      _ => false,
    };
  }

  FirebaseOptions optionsFor(TargetPlatform platform) => FirebaseOptions(
        apiKey: apiKey,
        appId: platform == TargetPlatform.iOS ? iosAppId : androidAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        iosBundleId: platform == TargetPlatform.iOS && iosBundleId.isNotEmpty
            ? iosBundleId
            : null,
      );
}

class FirebaseNotificationService implements NotificationService {
  FirebaseNotificationService()
      : _config = _FirebaseMobileConfig.fromDartDefines();

  static const _enabledKey = 'pollo_movil.push_notifications_enabled';
  static const _secureStorage = FlutterSecureStorage();

  final _FirebaseMobileConfig _config;
  final _foregroundController =
      StreamController<PushNotification>.broadcast();
  final _openedController = StreamController<PushNotification>.broadcast();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Future<void>? _initializing;
  bool _initialized = false;

  @override
  bool get isAvailable => _config.supports(defaultTargetPlatform);

  @override
  Future<bool> get isEnabled async {
    if (!isAvailable) return false;
    return await _secureStorage.read(key: _enabledKey) == 'true';
  }

  @override
  Future<void> initialize() async {
    if (!isAvailable) return;
    if (_initialized) {
      final enabled = await isEnabled;
      await FirebaseMessaging.instance.setAutoInitEnabled(enabled);
      if (enabled) await _registerAuthorizedDeviceToken();
      return;
    }
    final pending = _initializing;
    if (pending != null) {
      await pending;
      return;
    }

    final initialization = _initializeFirebase();
    _initializing = initialization;
    try {
      await initialization;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeFirebase() async {
    final platform = defaultTargetPlatform;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _config.optionsFor(platform));
    }
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(await isEnabled);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      _foregroundController.add(_fromRemoteMessage(message));
    });
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _openedController.add(_fromRemoteMessage(message));
    });
    _tokenSubscription = messaging.onTokenRefresh.listen((token) async {
      if (await isEnabled) await registerToken(token);
    });
    _initialized = true;

    if (await isEnabled) await _registerAuthorizedDeviceToken();
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (!isAvailable) return false;
    await initialize();

    if (!enabled) {
      await unregisterCurrentDevice();
      await _secureStorage.write(key: _enabledKey, value: 'false');
      return true;
    }

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final permitted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!permitted) {
      await _secureStorage.write(key: _enabledKey, value: 'false');
      return false;
    }

    await _secureStorage.write(key: _enabledKey, value: 'true');
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await _registerAuthorizedDeviceToken();
    return true;
  }

  Future<void> _registerAuthorizedDeviceToken() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();
    final permitted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!await isEnabled) return;
    if (!permitted) {
      await unregisterCurrentDevice();
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      var apnsToken = await messaging.getAPNSToken();
      for (var attempt = 0; apnsToken == null && attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        apnsToken = await messaging.getAPNSToken();
      }
      if (apnsToken == null) {
        debugPrint('[Pollo Móvil] APNs token pending; registration will retry later.');
        return;
      }
    }

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) await registerToken(token);
  }

  @override
  Future<String?> getDeviceToken() async {
    if (!isAvailable || !await isEnabled) return null;
    await initialize();
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('[Pollo Móvil] Push token unavailable: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> registerToken(String token) async {
    if (!isAvailable || token.isEmpty) return;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return;
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await client.functions.invoke(
        'device_tokens',
        body: {'action': 'register', 'token': token, 'platform': platform},
      );
    } catch (error) {
      // Offline registration is retried on the next authenticated app start.
      debugPrint('[Pollo Móvil] Push token registration deferred: ${error.runtimeType}');
    }
  }

  @override
  Future<void> unregisterCurrentDevice() async {
    await _secureStorage.write(key: _enabledKey, value: 'false');
    if (!isAvailable) return;
    try {
      await initialize();
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } catch (error) {
      debugPrint('[Pollo Móvil] Push initialization during revocation failed: ${error.runtimeType}');
    }

    try {
      final client = Supabase.instance.client;
      final token = await FirebaseMessaging.instance.getToken();
      if (client.auth.currentSession != null && token != null && token.isNotEmpty) {
        try {
          await client.functions.invoke(
            'device_tokens',
            body: {'action': 'unregister', 'token': token},
          );
        } catch (error) {
          debugPrint('[Pollo Móvil] Push token removal deferred: ${error.runtimeType}');
        }
      }
    } catch (error) {
      debugPrint('[Pollo Móvil] Push token removal deferred: ${error.runtimeType}');
    }

    try {
      // Revoke the FCM token too, so a failed offline API request cannot leave
      // notifications for the previous account routable to this installation.
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      // Sign-out should still proceed if Firebase or the network is unavailable.
      debugPrint('[Pollo Móvil] Push token revocation deferred: ${error.runtimeType}');
    }
  }

  @override
  Stream<PushNotification> get onForegroundMessage =>
      _foregroundController.stream;

  @override
  Stream<PushNotification> get onNotificationOpened => _openedController.stream;

  @override
  Future<PushNotification?> getInitialMessage() async {
    if (!isAvailable) return null;
    await initialize();
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : _fromRemoteMessage(message);
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _foregroundController.close();
    await _openedController.close();
  }

  PushNotification _fromRemoteMessage(RemoteMessage message) => PushNotification(
        title: message.notification?.title ?? '',
        body: message.notification?.body ?? '',
        data: Map<String, dynamic>.from(message.data),
      );
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = FirebaseNotificationService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

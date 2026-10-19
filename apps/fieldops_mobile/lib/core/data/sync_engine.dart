import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: unused_import — unawaited used in start()

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
const _maxRetries = 5;
const _syncIntervalSeconds = 15;

class SyncEngine {
  SyncEngine({
    required this.database,
    required this.supabaseClient,
  });

  final LocalDatabase database;
  final SupabaseClient supabaseClient;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  void start() {
    _timer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (!results.contains(ConnectivityResult.none)) {
          unawaited(syncPendingEvents().catchError((Object error) {
            debugPrint('[Pollo Móvil] Reconnect sync failed: $error');
          }));
        }
      },
      onError: (Object error) =>
          debugPrint('[Pollo Móvil] Connectivity stream failed: $error'),
    );
    _timer = Timer.periodic(
      const Duration(seconds: _syncIntervalSeconds),
      (_) => unawaited(syncPendingEvents().catchError((Object error) {
        debugPrint('[Pollo Móvil] Background sync failed: $error');
      })),
    );
    // Reconsider events parked for another account before the initial flush.
    unawaited(database.resumeWaitingEvents().then((_) => syncPendingEvents()).catchError(
      (Object e) => debugPrint('[Pollo Móvil] Initial sync failed: $e'),
    ));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
  }

  Future<void> syncPendingEvents() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return;

      final events = await database.pendingEventsByAge();
      for (final event in events) {
        await _syncSingleEvent(event);
      }

      // Remove only events already confirmed by the server; rejected records
      // stay in the local outbox until a person chooses to retry them.
      await database.cleanSynced();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncSingleEvent(PendingEvent event) async {
    try {
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(event.payload) as Map<String, dynamic>;
      } on FormatException catch (e) {
        await database.markPermanentlyFailed(
          event.id,
          'Malformed JSON payload (permanent): $e',
        );
        _reportDeadEvent(event, 'malformed_json', e);
        return;
      }

      if (event.eventType == 'restaurant_ops') {
        final queuedBy = payload['queued_by_user_id'];
        final activeUser = supabaseClient.auth.currentUser?.id;
        if (queuedBy is! String || activeUser == null || queuedBy != activeUser) {
          await database.markWaitingForAccount(event.id);
          return;
        }
        if (payload['action'] == 'record_time_event' && payload['branch_id'] is String &&
            await database.hasEarlierUnresolvedRestaurantClockEvent(
              currentEvent: event,
              branchId: payload['branch_id'] as String,
              actorId: queuedBy,
            )) {
          return;
        }
        final taskId = payload['task_id'];
        final branchId = payload['branch_id'];
        final partId = payload['part_id'];
        if (payload['action'] == 'task_action' &&
            taskId is String &&
            branchId is String &&
            (partId == null || partId is String) &&
            await database.hasEarlierUnresolvedRestaurantTaskAction(
              currentEvent: event,
              branchId: branchId,
              actorId: queuedBy,
              taskId: taskId,
              partId: partId as String?,
            )) {
          return;
        }
        final coverRequestId = payload['request_id'];
        if (payload['action'] == 'cancel_shift_cover_request' &&
            coverRequestId is String &&
            branchId is String &&
            await database.hasEarlierUnresolvedRestaurantShiftCoverRequest(
              currentEvent: event,
              branchId: branchId,
              actorId: queuedBy,
              clientEventId: coverRequestId,
            )) {
          return;
        }
      }

      switch (event.eventType) {
        case 'clock_event':
          await _syncClockEvent(event, payload);
        case 'photo_presign':
          await _syncPhotoPresign(event, payload);
        case 'photo_finalize':
          await _syncPhotoFinalize(event, payload);
        case 'restaurant_ops':
          await _syncRestaurantOps(event, payload);
        default:
          await database.markPermanentlyFailed(
            event.id,
            'Unknown event type: ${event.eventType}',
          );
          _reportDeadEvent(event, 'unknown_event_type', null);
      }
    } on Exception catch (e) {
      final newRetryCount = event.retryCount + 1;
      if (newRetryCount >= _maxRetries) {
        await database.markPermanentlyFailed(
          event.id,
          'Max retries exceeded: $e',
        );
        _reportDeadEvent(event, 'max_retries_exceeded', e);
      } else {
        await database.markFailed(event.id, '$e', newRetryCount);
      }
    }
  }

  /// A permanently-failed outbox event is DATA LOSS — a clock-in or photo
  /// the worker believes was recorded but that will never reach the server
  /// (payroll disputes start exactly here). It must never die silently.
  /// Payload is NOT attached: it can contain GPS coordinates.
  void _reportDeadEvent(PendingEvent event, String reason, Object? cause) {
    unawaited(
      Sentry.captureException(
        StateError(
          'Outbox event permanently failed ($reason): '
          '${event.eventType} local-id=${event.id}'
          '${cause != null ? ' cause=$cause' : ''}',
        ),
        withScope: (scope) {
          scope.setTag('source', 'sync_engine');
          scope.setTag('dead_letter_reason', reason);
          scope.setTag('event_type', event.eventType);
        },
      ),
    );
  }

  Future<void> _syncClockEvent(
    PendingEvent event,
    Map<String, dynamic> payload,
  ) async {
    final response = await supabaseClient.functions.invoke(
      'sync_events',
      headers: {
        // Use the stable local row ID so retries replay the same request
        // rather than creating duplicate events on the server.
        'Idempotency-Key': 'local-event-${event.id}',
        'X-Client-Version': 'pollo-movil-mobile',
      },
      body: {
        // Stable batch_id ensures the entire request body is idempotent on retry.
        'batch_id': 'batch-${event.id}',
        'clock_events': [payload],
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Malformed sync response');
    }

    final accepted =
        (data['accepted'] as List<dynamic>? ?? const []).cast<String>();
    final duplicates =
        (data['duplicates'] as List<dynamic>? ?? const []).cast<String>();
    final eventId = payload['id'] as String;

    if (accepted.contains(eventId) || duplicates.contains(eventId)) {
      await database.markSynced(event.id);
      return;
    }

    final rejected = data['rejected'] as List<dynamic>? ?? const [];
    if (rejected.isNotEmpty) {
      final first = rejected.first;
      if (first is Map<String, dynamic>) {
        final reason = first['reason'] as String? ?? 'unknown';
        if (reason == 'forbidden_job' || reason == 'invalid_payload') {
          await database.markPermanentlyFailed(
            event.id,
            'Rejected: $reason',
          );
          return;
        }
      }
    }

    throw Exception('Clock event not accepted or duplicated');
  }

  Future<void> _syncPhotoPresign(
    PendingEvent event,
    Map<String, dynamic> payload,
  ) async {
    final response = await supabaseClient.functions.invoke(
      'media_presign',
      headers: {
        'Idempotency-Key': 'local-event-${event.id}',
        'X-Client-Version': 'pollo-movil-mobile',
      },
      body: payload,
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Malformed presign response');
    }

    await database.markSynced(event.id);
  }

  Future<void> _syncPhotoFinalize(
    PendingEvent event,
    Map<String, dynamic> payload,
  ) async {
    final response = await supabaseClient.functions.invoke(
      'media_finalize',
      headers: {
        'Idempotency-Key': 'local-event-${event.id}',
        'X-Client-Version': 'pollo-movil-mobile',
      },
      body: payload,
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Malformed finalize response');
    }

    await database.markSynced(event.id);
  }

  Future<void> _syncRestaurantOps(
    PendingEvent event,
    Map<String, dynamic> payload,
  ) async {
    if (!await _belongsToActiveAccount(event, payload)) return;
    if (payload['action'] == 'upload_evidence') {
      await _syncRestaurantEvidence(event, payload);
      return;
    }

    final evidencePath = payload['evidence_path'];
    if (evidencePath is String &&
        await database.hasOutstandingRestaurantEvidence(evidencePath)) {
      // Keep completion behind its photo registration. The evidence row remains
      // retryable and the task must not appear complete without its required proof.
      return;
    }

    try {
      final requestPayload = Map<String, dynamic>.from(payload);
      if (payload['action'] == 'task_action') {
        requestPayload['offline_replay'] = true;
        requestPayload['occurred_at'] =
            event.occurredAt.toUtc().toIso8601String();
      } else if (payload['action'] == 'record_area_inspection' ||
          payload['action'] == 'inspect_waste' ||
          payload['action'] == 'create_incident') {
        requestPayload['offline_replay'] = true;
        requestPayload['occurred_at'] =
            event.occurredAt.toUtc().toIso8601String();
      }
      final response = await supabaseClient.functions.invoke(
        'restaurant_ops',
        headers: {
          'Idempotency-Key': 'local-event-${event.id}',
          'X-Client-Version': 'pollo-movil',
        },
        body: requestPayload,
      );
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Malformed restaurant operation response');
      }
      await database.markSynced(event.id);
    } on FunctionException catch (error) {
      if (error.status >= 400 && error.status < 500 &&
          !const {408, 425, 429}.contains(error.status)) {
        await database.markPermanentlyFailed(
          event.id,
          'Restaurant operation rejected (${error.status}); refresh the shift before retrying.',
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> _syncRestaurantEvidence(
    PendingEvent event,
    Map<String, dynamic> payload,
  ) async {
    final branchId = payload['branch_id'];
    final taskId = payload['task_id'];
    final eventId = payload['client_event_id'];
    final rawPath = payload['file_path'];
    final objectPath = payload['object_path'];
    final partId = payload['part_id'];
    final size = payload['file_size_bytes'];
    if (branchId is! String ||
        taskId is! String ||
        eventId != event.id ||
        rawPath is! String ||
        objectPath != '$branchId/$taskId/$eventId.jpg' ||
        (partId != null && partId is! String) ||
        size is! num ||
        size <= 0 ||
        size > 10 * 1024 * 1024) {
      await database.markPermanentlyFailed(
        event.id,
        'Saved evidence metadata is invalid. Capture the image again.',
      );
      _reportDeadEvent(event, 'invalid_restaurant_evidence', null);
      return;
    }

    final documents = await getApplicationDocumentsDirectory();
    final evidenceRoot = Directory(
      '${documents.path}${Platform.pathSeparator}pollo_movil_evidence',
    ).absolute.path;
    final file = File(rawPath).absolute;
    if (!file.path.startsWith('$evidenceRoot${Platform.pathSeparator}')) {
      await database.markPermanentlyFailed(
        event.id,
        'Saved evidence is outside the Pollo Móvil private evidence folder.',
      );
      _reportDeadEvent(event, 'invalid_restaurant_evidence_path', null);
      return;
    }

    final folder = '$branchId/$taskId';
    final fileName = '$eventId.jpg';
    final storage = supabaseClient.storage.from('restaurant-evidence');
    if (!await _belongsToActiveAccount(event, payload)) return;
    final existing = await storage.list(
      path: folder,
      searchOptions: SearchOptions(search: fileName, limit: 10),
    );
    final objectExists = existing.any((object) => object.name == fileName);

    if (!objectExists) {
      if (!await file.exists() || await file.length() != size) {
        await database.markPermanentlyFailed(
          event.id,
          'Saved evidence file is missing or incomplete. Capture the image again.',
        );
        _reportDeadEvent(event, 'missing_restaurant_evidence_file', null);
        return;
      }
      if (!await _belongsToActiveAccount(event, payload)) return;
      await storage.uploadBinary(
        objectPath as String,
        await file.readAsBytes(),
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600',
          upsert: false,
        ),
      );
    }

    try {
      if (!await _belongsToActiveAccount(event, payload)) return;
      final response = await supabaseClient.functions.invoke(
        'restaurant_ops',
        headers: {
          'Idempotency-Key': 'local-event-${event.id}',
          'X-Client-Version': 'pollo-movil',
        },
        body: {
          'action': 'register_evidence',
          'branch_id': branchId,
          'task_id': taskId,
          if (partId is String) 'part_id': partId,
          'object_path': objectPath,
          'mime_type': 'image/jpeg',
          'file_size_bytes': size,
        },
      );
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Malformed restaurant evidence registration response');
      }
    } on FunctionException catch (error) {
      if (error.status >= 400 && error.status < 500 &&
          !const {408, 425, 429}.contains(error.status)) {
        await database.markPermanentlyFailed(
          event.id,
          'Evidence registration rejected (${error.status}); capture a new image after refreshing the task.',
        );
        _reportDeadEvent(event, 'restaurant_evidence_rejected', error);
        return;
      }
      rethrow;
    }

    await database.markSynced(event.id);
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      debugPrint('[Pollo Móvil] Uploaded evidence cleanup deferred: $error');
    }
  }

  Future<bool> _belongsToActiveAccount(
    PendingEvent event,
    Map<String, dynamic> payload,
  ) async {
    final queuedBy = payload['queued_by_user_id'];
    final activeUser = supabaseClient.auth.currentUser?.id;
    if (queuedBy is String && activeUser != null && queuedBy == activeUser) {
      return true;
    }
    await database.markWaitingForAccount(event.id);
    return false;
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final database = ref.watch(localDatabaseProvider);
  final engine = SyncEngine(
    database: database,
    supabaseClient: Supabase.instance.client,
  );
  ref.onDispose(engine.stop);
  return engine;
});

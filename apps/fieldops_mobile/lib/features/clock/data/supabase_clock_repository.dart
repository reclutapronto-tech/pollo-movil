import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseClockRepository implements ClockRepository {
  SupabaseClockRepository(
    this._client, {
    LocalDatabase? localDatabase,
    Uuid? uuid,
  })  : _localDatabase = localDatabase,
        _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final LocalDatabase? _localDatabase;
  final Uuid _uuid;

  @override
  Future<ClockActionResult> clockIn({required String jobId}) =>
      _submitClockEvent(jobId: jobId, subtype: 'clock_in');

  @override
  Future<ClockActionResult> clockOut({required String jobId}) =>
      _submitClockEvent(jobId: jobId, subtype: 'clock_out');

  @override
  Future<ClockActionResult> breakStart({required String jobId}) =>
      _submitClockEvent(jobId: jobId, subtype: 'break_start');

  @override
  Future<ClockActionResult> breakEnd({required String jobId}) =>
      _submitClockEvent(jobId: jobId, subtype: 'break_end');

  Future<ClockActionResult> _submitClockEvent({
    required String jobId,
    required String subtype,
  }) async {
    // Resolve position + build the clock-event payload before the try/catch
    // so location errors still surface as errors (they're not offline).
    final position = await _resolvePosition();
    final eventId = _uuid.v4();
    final occurredAt = DateTime.now().toUtc();

    // NOTE: this object is the byte-identical inner payload that the sync
    // engine expects. `SyncEngine._syncClockEvent` reads this stored payload
    // and wraps it as `{batch_id: 'batch-<id>', clock_events: [payload]}`.
    // Keep the shape in lockstep with the online body below.
    final clockEvent = <String, dynamic>{
      'id': eventId,
      'job_id': jobId,
      'event_subtype': subtype,
      'occurred_at': occurredAt.toIso8601String(),
      'gps': {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy_m': position.accuracy,
      },
    };

    try {
      final response = await _client.functions.invoke(
        'sync_events',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'batch_id': _uuid.v4(),
          'clock_events': [clockEvent],
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ClockRepositoryException.unknown(
          'Clock response was malformed.',
        );
      }

      final accepted =
          (payload['accepted'] as List<dynamic>? ?? const []).cast<String>();
      final duplicates =
          (payload['duplicates'] as List<dynamic>? ?? const []).cast<String>();
      final rejected = payload['rejected'] as List<dynamic>? ?? const [];

      if (accepted.contains(eventId) || duplicates.contains(eventId)) {
        return ClockActionResult(eventId: eventId, occurredAt: occurredAt);
      }

      if (rejected.isNotEmpty) {
        final firstRejected = rejected.first;
        if (firstRejected is Map<String, dynamic>) {
          final reason = firstRejected['reason'] as String? ?? 'unknown';
          switch (reason) {
            case 'invalid_geofence':
              throw const ClockRepositoryException.unknown(
                'You are outside the job geofence.',
              );
            case 'forbidden_job':
              throw const ClockRepositoryException.unknown(
                'This job is no longer assigned to you.',
              );
          }
        }
      }

      throw const ClockRepositoryException.unknown();
    } on SocketException {
      return _enqueueOrThrow(
        eventId: eventId,
        jobId: jobId,
        occurredAt: occurredAt,
        clockEvent: clockEvent,
      );
    } on HttpException {
      return _enqueueOrThrow(
        eventId: eventId,
        jobId: jobId,
        occurredAt: occurredAt,
        clockEvent: clockEvent,
      );
    } on FunctionException catch (error) {
      if (error.status == 0) {
        return _enqueueOrThrow(
          eventId: eventId,
          jobId: jobId,
          occurredAt: occurredAt,
          clockEvent: clockEvent,
        );
      }
      throw ClockRepositoryException.unknown(
        'Clock request failed (${error.status}).',
      );
    }
    // NOTE: TimeoutException and PermissionDeniedException intentionally
    // propagate — they originate from `_resolvePosition()` above and must
    // surface to the worker. Server-side rejections (invalid_geofence,
    // forbidden_job) are also left to throw above — we only queue on
    // network-offline signatures.
  }

  /// Writes the event to the local outbox if a `LocalDatabase` is wired up,
  /// otherwise preserves the legacy "offline" throw so tests / unconfigured
  /// builds behave exactly as before.
  Future<ClockActionResult> _enqueueOrThrow({
    required String eventId,
    required String jobId,
    required DateTime occurredAt,
    required Map<String, dynamic> clockEvent,
  }) async {
    final db = _localDatabase;
    if (db == null) {
      throw const ClockRepositoryException.offline();
    }

    await db.into(db.pendingEvents).insert(
          PendingEventsCompanion.insert(
            id: eventId,
            eventType: 'clock_event',
            jobId: jobId,
            payload: jsonEncode(clockEvent),
            occurredAt: occurredAt,
            retryCount: const Value(0),
            syncStatus: const Value('pending'),
          ),
        );

    return ClockActionResult(
      eventId: eventId,
      occurredAt: occurredAt,
      queued: true,
    );
  }

  Future<Position> _resolvePosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const ClockRepositoryException.locationUnavailable();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const ClockRepositoryException.locationDenied();
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).timeout(const Duration(seconds: 8));
  }
}

import 'dart:io';

import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_clock_repository.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseCrewClockRepository implements CrewClockRepository {
  const SupabaseCrewClockRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<ClockActionResult> clockInWorker({
    required String workerId,
    required String jobId,
  }) => _submit(workerId: workerId, jobId: jobId, subtype: 'clock_in');

  @override
  Future<ClockActionResult> clockOutWorker({
    required String workerId,
    required String jobId,
  }) => _submit(workerId: workerId, jobId: jobId, subtype: 'clock_out');

  Future<ClockActionResult> _submit({
    required String workerId,
    required String jobId,
    required String subtype,
  }) async {
    try {
      // Use foreman's GPS (their device)
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));

      final eventId = _uuid.v4();
      final occurredAt = DateTime.now().toUtc();

      final response = await _client.functions.invoke(
        'sync_events',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'batch_id': _uuid.v4(),
          'clock_events': [
            {
              'id': eventId,
              'job_id': jobId,
              'event_subtype': subtype,
              'occurred_at': occurredAt.toIso8601String(),
              'gps': {
                'lat': position.latitude,
                'lng': position.longitude,
                'accuracy_m': position.accuracy,
              },
              // Metadata shows this was a crew clock-in by foreman
              'notes': 'Crew clock-in by foreman on behalf of worker $workerId',
            },
          ],
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ClockRepositoryException.unknown('Crew clock response malformed.');
      }

      return ClockActionResult(eventId: eventId, occurredAt: occurredAt);
    } on SocketException {
      throw const ClockRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const ClockRepositoryException.offline();
      throw ClockRepositoryException.unknown('Crew clock failed (${error.status}).');
    }
  }
}

import 'package:fieldops_mobile/features/time_corrections/domain/time_correction_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseTimeCorrectionRepository implements TimeCorrectionRepository {
  const SupabaseTimeCorrectionRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<List<TimeCorrection>> fetchCorrections({
    String? workerId,
    String? jobId,
    String status = 'pending',
  }) async {
    try {
      final queryParams = <String, String>{'status': status};
      if (workerId != null) queryParams['worker_id'] = workerId;
      if (jobId != null) queryParams['job_id'] = jobId;

      final response = await _client.functions.invoke(
        'time_corrections',
        method: HttpMethod.get,
        headers: {'X-Client-Version': 'fieldops-mobile'},
        queryParameters: queryParams,
      );

      final data = response.data as Map<String, dynamic>;
      final corrections = data['corrections'] as List<dynamic>? ?? [];

      return corrections
          .map((c) => TimeCorrection.fromJson(c as Map<String, dynamic>))
          .toList();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const TimeCorrectionException.offline();
      throw TimeCorrectionException('Failed to load corrections: ${error.details}');
    } catch (e) {
      throw TimeCorrectionException('Failed to load corrections: $e');
    }
  }

  @override
  Future<String> createCorrection({
    required String workerId,
    required String jobId,
    String? originalEventId,
    String? originalEventSubtype,
    DateTime? originalOccurredAt,
    required String correctedEventSubtype,
    required DateTime correctedOccurredAt,
    required String reason,
    String? evidenceNotes,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'time_corrections',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'create',
          'worker_id': workerId,
          'job_id': jobId,
          'original_event_id': originalEventId,
          'original_event_subtype': originalEventSubtype,
          'original_occurred_at': originalOccurredAt?.toIso8601String(),
          'corrected_event_subtype': correctedEventSubtype,
          'corrected_occurred_at': correctedOccurredAt.toIso8601String(),
          'reason': reason,
          'evidence_notes': evidenceNotes,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return data['correction_id'] as String;
    } on FunctionException catch (error) {
      if (error.status == 0) throw const TimeCorrectionException.offline();
      throw TimeCorrectionException('Failed to create correction: ${error.details}');
    } catch (e) {
      throw TimeCorrectionException('Failed to create correction: $e');
    }
  }

  @override
  Future<void> decideCorrection({
    required String correctionId,
    required String decision,
    String? reason,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'time_corrections',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'decide',
          'correction_id': correctionId,
          'decision': decision,
          'decision_reason': reason,
        },
      );

      if (response.status != 200 && response.status != 201) {
        throw const TimeCorrectionException('Failed to decide correction');
      }
    } on FunctionException catch (error) {
      if (error.status == 0) throw const TimeCorrectionException.offline();
      throw TimeCorrectionException('Failed to decide correction: ${error.details}');
    } catch (e) {
      throw TimeCorrectionException('Failed to decide correction: $e');
    }
  }
}

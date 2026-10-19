import 'dart:io';

import 'package:fieldops_mobile/features/safety/domain/safety_checklist.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseSafetyRepository implements SafetyRepository {
  const SupabaseSafetyRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<String> submitChecklist({
    required String jobId,
    required List<SafetyChecklistResponse> responses,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'safety',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'submit',
          'job_id': jobId,
          'responses': responses
              .map((r) => {
                    'question_id': r.questionId,
                    'answer': r.answer,
                    'answered_at': r.answeredAt.toUtc().toIso8601String(),
                  })
              .toList(),
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const SafetyRepositoryException('Safety response malformed.');
      }

      return payload['checklist_id'] as String? ?? '';
    } on SocketException {
      throw const SafetyRepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const SafetyRepositoryException('No connection available.');
      }
      throw SafetyRepositoryException(
        'Could not submit safety checklist (${error.status}).',
      );
    }
  }

  @override
  Future<bool> hasCompletedToday(String jobId) async {
    try {
      final response = await _client.functions.invoke(
        'safety',
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {
          'action': 'check',
          'job_id': jobId,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const SafetyRepositoryException('Safety check response malformed.');
      }

      return payload['completed'] as bool? ?? false;
    } on SocketException {
      throw const SafetyRepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const SafetyRepositoryException('No connection available.');
      }
      throw SafetyRepositoryException(
        'Could not verify safety status (${error.status}).',
      );
    }
  }
}

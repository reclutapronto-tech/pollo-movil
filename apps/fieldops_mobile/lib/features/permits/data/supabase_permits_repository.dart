import 'dart:io';

import 'package:fieldops_mobile/features/permits/domain/permits_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [PermitsRepository] that calls the `permits` edge function
/// with action `check_active`. The call is read-only and idempotent.
class SupabasePermitsRepository implements PermitsRepository {
  const SupabasePermitsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PermitCheckResult> checkActive({required String jobId}) async {
    try {
      final response = await _client.functions.invoke(
        'permits',
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {
          'action': 'check_active',
          'job_id': jobId,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const PermitsRepositoryException.unknown(
          'Permit check response malformed.',
        );
      }

      final required = payload['required'] as bool? ?? false;
      final requiredType = payload['required_type'] as String?;
      final activeRaw = payload['active_permit'];
      final activePermit = activeRaw is Map<String, dynamic>
          ? ActivePermit.fromJson(activeRaw)
          : null;

      return PermitCheckResult(
        required: required,
        requiredType: requiredType,
        activePermit: activePermit,
      );
    } on SocketException {
      throw const PermitsRepositoryException.offline();
    } on HttpException {
      throw const PermitsRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PermitsRepositoryException.offline();
      }
      final serverMessage = error.details?.toString() ??
          'Could not verify permit status (${error.status}).';
      throw PermitsRepositoryException.unknown(serverMessage);
    }
  }
}

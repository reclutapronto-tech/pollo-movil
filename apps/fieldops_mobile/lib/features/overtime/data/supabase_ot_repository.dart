import 'dart:io';

import 'package:fieldops_mobile/features/overtime/domain/ot_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseOTRepository implements OTRepository {
  const SupabaseOTRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<String> submitRequest({
    required String jobId,
    double? totalHours,
    String? notes,
    String? photoEventId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'ot',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'request',
          'job_id': jobId,
          if (totalHours != null) 'total_hours': totalHours,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (photoEventId != null) 'photo_event_id': photoEventId,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const OTRepositoryException.unknown(
          'OT response was malformed.',
        );
      }

      return payload['ot_request_id'] as String? ?? '';
    } on SocketException {
      throw const OTRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const OTRepositoryException.offline();
      throw OTRepositoryException.unknown(
        'OT request failed (${error.status}).',
      );
    }
  }

  @override
  Future<List<OTRequest>> fetchPendingRequests() async {
    try {
      final response = await _client.functions.invoke(
        'ot',
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {'action': 'pending'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const OTRepositoryException.unknown(
          'OT pending response was malformed.',
        );
      }

      final items = payload['requests'] as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(OTRequest.fromJson)
          .toList();
    } on SocketException {
      throw const OTRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const OTRepositoryException.offline();
      throw OTRepositoryException.unknown(
        'Could not fetch OT requests (${error.status}).',
      );
    }
  }

  @override
  Future<void> approveRequest(String requestId) async {
    try {
      await _client.functions.invoke(
        'ot',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'approve',
          'ot_request_id': requestId,
        },
      );
    } on SocketException {
      throw const OTRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const OTRepositoryException.offline();
      throw OTRepositoryException.unknown(
        'Could not approve OT request (${error.status}).',
      );
    }
  }

  @override
  Future<void> denyRequest(String requestId, {String? reason}) async {
    try {
      await _client.functions.invoke(
        'ot',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'deny',
          'ot_request_id': requestId,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
    } on SocketException {
      throw const OTRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const OTRepositoryException.offline();
      throw OTRepositoryException.unknown(
        'Could not deny OT request (${error.status}).',
      );
    }
  }
}

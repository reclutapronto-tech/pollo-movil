import 'dart:io';

import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final ptoRepositoryProvider = Provider<PTORepository>((ref) {
  return SupabasePTORepository();
});

class SupabasePTORepository implements PTORepository {
  final _functions = Supabase.instance.client.functions;
  final _uuid = const Uuid();

  @override
  Future<String> submitRequest({
    required String type,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
  }) async {
    final response = await _functions.invoke('pto', body: {
      'action': 'request',
      'pto_type': type,
      'start_date': _dateString(startDate),
      'end_date': _dateString(endDate),
      'notes': notes,
    });

    final data = response.data as Map<String, dynamic>;
    if (data['status'] != 'submitted') {
      throw PTORepositoryException(
        data['message'] as String? ?? 'Failed to submit PTO request',
      );
    }

    final pto = data['pto_request'] as Map<String, dynamic>;
    return pto['id'] as String;
  }

  @override
  Future<List<PTORequest>> fetchMyRequests() async {
    final response = await _functions.invoke(
      'pto',
      method: HttpMethod.get,
    );

    final data = response.data as Map<String, dynamic>;
    final requests = (data['requests'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(PTORequest.fromJson)
        .toList();

    return requests;
  }

  @override
  Future<PTOBalance> fetchMyBalance() async {
    try {
      final response = await _functions.invoke('pto', body: {
        'action': 'balance',
      });

      final data = response.data as Map<String, dynamic>;
      return PTOBalance.fromJson(data['balance'] as Map<String, dynamic>);
    } on SocketException {
      throw const PTORepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PTORepositoryException('No connection available.');
      }
      throw PTORepositoryException(
        'Could not fetch PTO balance (${error.status}).',
      );
    }
  }

  @override
  Future<List<PTORequest>> fetchPendingApprovals() async {
    try {
      final response = await _functions.invoke('pto', body: {
        'action': 'pending_approvals',
      });

      final data = response.data as Map<String, dynamic>;
      final items = data['requests'] as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(PTORequest.fromJson)
          .toList();
    } on SocketException {
      throw const PTORepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PTORepositoryException('No connection available.');
      }
      throw PTORepositoryException(
        'Could not fetch pending PTO requests (${error.status}).',
      );
    }
  }

  @override
  Future<void> approveRequest(String requestId) async {
    try {
      await _functions.invoke('pto', headers: {
        'Idempotency-Key': _uuid.v4(),
        'X-Client-Version': 'fieldops-mobile',
      }, body: {
        'action': 'approve',
        'request_id': requestId,
      });
    } on SocketException {
      throw const PTORepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PTORepositoryException('No connection available.');
      }
      throw PTORepositoryException(
        'Could not approve PTO request (${error.status}).',
      );
    }
  }

  @override
  Future<void> denyRequest(String requestId, {String? reason}) async {
    try {
      await _functions.invoke('pto', headers: {
        'Idempotency-Key': _uuid.v4(),
        'X-Client-Version': 'fieldops-mobile',
      }, body: {
        'action': 'deny',
        'request_id': requestId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
    } on SocketException {
      throw const PTORepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PTORepositoryException('No connection available.');
      }
      throw PTORepositoryException(
        'Could not deny PTO request (${error.status}).',
      );
    }
  }

  @override
  Future<List<PtoAllocation>> fetchAllocations({int? year}) async {
    try {
      final response = await _functions.invoke('pto', body: {
        'action': 'allocations_list',
        if (year != null) 'year': year,
      });
      final data = response.data as Map<String, dynamic>;
      final items = data['allocations'] as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(PtoAllocation.fromJson)
          .toList();
    } on SocketException {
      throw const PTORepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PTORepositoryException('No connection available.');
      }
      throw PTORepositoryException(
        'Could not fetch PTO allocations (${error.status}).',
      );
    }
  }

  @override
  Future<void> upsertAllocation({
    required String userId,
    required String ptoType,
    required int year,
    required num totalDays,
  }) async {
    try {
      await _functions.invoke(
        'pto',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'allocations_upsert',
          'user_id': userId,
          'pto_type': ptoType,
          'year': year,
          'total_days': totalDays,
        },
      );
    } on SocketException {
      throw const PTORepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const PTORepositoryException('No connection available.');
      }
      throw PTORepositoryException(
        'Could not save allocation (${error.status}).',
      );
    }
  }

  String _dateString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

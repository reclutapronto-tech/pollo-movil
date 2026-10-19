import 'dart:io';

import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseScheduleRepository implements ScheduleRepository {
  const SupabaseScheduleRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<List<WorkerScheduleShift>> fetchMySchedule({
    DateTime? from,
    DateTime? to,
  }) async {
    final start = from ?? DateTime.now().toUtc();
    final end = to ?? start.add(const Duration(days: 13));

    try {
      final response = await _client.functions.invoke(
        'schedule',
        method: HttpMethod.get,
        queryParameters: {
          'date_from': _asDate(start),
          'date_to': _asDate(end),
        },
        headers: const {'X-Client-Version': 'fieldops-mobile'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ScheduleRepositoryException.unknown(
          'Schedule response was malformed.',
        );
      }

      final shifts = payload['shifts'] as List<dynamic>? ?? const [];
      return shifts
          .whereType<Map<String, dynamic>>()
          .map(WorkerScheduleShift.fromJson)
          .toList(growable: false);
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on HttpException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Schedule request failed (${error.status}).',
      );
    }
  }

  @override
  Future<String> requestShiftSwap({
    required String shiftId,
    String? notes,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'schedule',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'swap_request',
          'shift_id': shiftId,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ScheduleRepositoryException.unknown(
          'Swap response was malformed.',
        );
      }

      return payload['swap_request_id'] as String? ?? '';
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not submit swap request (${error.status}).',
      );
    }
  }

  @override
  Future<List<CrewScheduleShift>> fetchCrewSchedule({
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now().toUtc();
    final start = from ?? DateTime.utc(now.year, now.month, now.day);
    final end = to ?? start.add(const Duration(days: 1));

    try {
      final response = await _client.functions.invoke(
        'schedule',
        method: HttpMethod.get,
        queryParameters: {
          'view': 'crew',
          'date_from': _asDate(start),
          'date_to': _asDate(end),
        },
        headers: const {'X-Client-Version': 'fieldops-mobile'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ScheduleRepositoryException.unknown(
          'Crew schedule response was malformed.',
        );
      }

      final shifts = payload['shifts'] as List<dynamic>? ?? const [];
      return shifts
          .whereType<Map<String, dynamic>>()
          .map(CrewScheduleShift.fromJson)
          .toList(growable: false);
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Crew schedule request failed (${error.status}).',
      );
    }
  }

  @override
  Future<bool> saveCrewReorder(List<CrewScheduleShift> shifts) async {
    try {
      final response = await _client.functions.invoke(
        'schedule',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'crew_reorder',
          'shifts': shifts.map((s) => s.toReorderPayload()).toList(),
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ScheduleRepositoryException.unknown(
          'Reorder response was malformed.',
        );
      }

      return payload['success'] as bool? ?? false;
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not save reorder (${error.status}).',
      );
    }
  }

  String _asDate(DateTime value) => value.toUtc().toIso8601String().split('T').first;

  @override
  Future<List<SwapRequest>> fetchSwapRequests({String status = 'pending'}) async {
    try {
      final response = await _client.functions.invoke(
        'schedule',
        headers: const {'X-Client-Version': 'fieldops-mobile'},
        body: {'action': 'swap_list', 'status': status},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ScheduleRepositoryException.unknown(
          'Swap list response was malformed.',
        );
      }
      final items = payload['requests'] as List<dynamic>? ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(SwapRequest.fromJson)
          .toList(growable: false);
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not load swap requests (${error.status}).',
      );
    }
  }

  @override
  Future<void> approveSwap(String swapRequestId, {String? reason}) async {
    try {
      await _client.functions.invoke(
        'schedule',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'swap_decide',
          'swap_request_id': swapRequestId,
          'decision': 'approved',
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not approve swap (${error.status}).',
      );
    }
  }

  @override
  Future<void> denySwap(String swapRequestId, {required String reason}) async {
    try {
      await _client.functions.invoke(
        'schedule',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'swap_decide',
          'swap_request_id': swapRequestId,
          'decision': 'denied',
          'reason': reason,
        },
      );
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not deny swap (${error.status}).',
      );
    }
  }

  @override
  Future<void> cancelSwap(String swapRequestId) async {
    try {
      await _client.functions.invoke(
        'schedule',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'swap_cancel',
          'swap_request_id': swapRequestId,
        },
      );
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not cancel swap (${error.status}).',
      );
    }
  }

  @override
  Future<int> copyWeek({
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime targetStart,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'schedule',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'copy_week',
          'source_start': _asDate(sourceStart),
          'source_end': _asDate(sourceEnd),
          'target_start': _asDate(targetStart),
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ScheduleRepositoryException.unknown(
          'Copy-week response was malformed.',
        );
      }
      return (payload['copied_count'] as num?)?.toInt() ?? 0;
    } on SocketException {
      throw const ScheduleRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const ScheduleRepositoryException.offline();
      }
      throw ScheduleRepositoryException.unknown(
        'Could not copy the week (${error.status}).',
      );
    }
  }
}

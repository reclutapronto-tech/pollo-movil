import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';

abstract class ScheduleRepository {
  Future<List<WorkerScheduleShift>> fetchMySchedule({
    DateTime? from,
    DateTime? to,
  });

  /// Requests a shift swap with another worker.
  Future<String> requestShiftSwap({
    required String shiftId,
    String? notes,
  });

  /// Fetches shifts for the foreman's crew (today + tomorrow).
  Future<List<CrewScheduleShift>> fetchCrewSchedule({
    DateTime? from,
    DateTime? to,
  });

  /// Saves the reordered crew schedule to the backend.
  /// Returns true on success.
  Future<bool> saveCrewReorder(List<CrewScheduleShift> shifts);

  /// Supervisor-side: lists shift swap requests for the caller's company
  /// filtered by status (default pending).
  Future<List<SwapRequest>> fetchSwapRequests({String status = 'pending'});

  /// Supervisor-side: approves a pending swap request.
  Future<void> approveSwap(String swapRequestId, {String? reason});

  /// Supervisor-side: denies a pending swap request. Reason required.
  Future<void> denySwap(String swapRequestId, {required String reason});

  /// Worker-side: cancels one of the caller's own pending swap requests.
  Future<void> cancelSwap(String swapRequestId);

  /// Foreman/supervisor: copy the draft + published shifts from the week
  /// [sourceStart]..[sourceEnd] (inclusive) into a new week starting at
  /// [targetStart]. New shifts are inserted as `status='draft'` so the
  /// foreman can review before publishing. Returns the number of shifts
  /// copied (0 if the source week was empty).
  Future<int> copyWeek({
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime targetStart,
  });
}

enum SwapRequestStatus { pending, approved, denied, cancelled }

SwapRequestStatus _swapStatusFromString(String value) => switch (value) {
      'approved' => SwapRequestStatus.approved,
      'denied' => SwapRequestStatus.denied,
      'cancelled' => SwapRequestStatus.cancelled,
      _ => SwapRequestStatus.pending,
    };

/// Summary of the shift a swap refers to, as returned by `schedule.swap_list`.
class SwapShiftInfo {
  const SwapShiftInfo({
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.jobId,
    required this.jobName,
  });

  factory SwapShiftInfo.fromJson(Map<String, dynamic> json) {
    final dateStr = json['shift_date'] as String? ?? '';
    final parsed = DateTime.tryParse(dateStr) ?? DateTime.now().toUtc();
    return SwapShiftInfo(
      shiftDate: DateTime.utc(parsed.year, parsed.month, parsed.day),
      startTime: json['start_time'] as String? ?? '--:--',
      endTime: json['end_time'] as String? ?? '--:--',
      jobId: json['job_id'] as String? ?? '',
      jobName: json['job_name'] as String? ?? 'Unnamed job',
    );
  }

  final DateTime shiftDate;
  final String startTime;
  final String endTime;
  final String jobId;
  final String jobName;
}

class SwapRequest {
  const SwapRequest({
    required this.id,
    required this.shiftId,
    required this.requesterId,
    required this.requesterName,
    required this.status,
    required this.createdAt,
    this.swapWithUserId,
    this.swapWithName,
    this.notes,
    this.decidedAt,
    this.decidedBy,
    this.decisionReason,
    this.shift,
  });

  factory SwapRequest.fromJson(Map<String, dynamic> json) {
    final shiftJson = json['shift'];
    return SwapRequest(
      id: json['id'] as String? ?? '',
      shiftId: json['shift_id'] as String? ?? '',
      requesterId: json['requester_id'] as String? ?? '',
      requesterName: json['requester_name'] as String? ?? 'Unknown',
      swapWithUserId: json['swap_with_user_id'] as String?,
      swapWithName: json['swap_with_name'] as String?,
      notes: json['notes'] as String?,
      status: _swapStatusFromString(json['status'] as String? ?? 'pending'),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      decidedAt: json['decided_at'] != null
          ? DateTime.tryParse(json['decided_at'] as String)
          : null,
      decidedBy: json['decided_by'] as String?,
      decisionReason: json['decision_reason'] as String?,
      shift: shiftJson is Map<String, dynamic>
          ? SwapShiftInfo.fromJson(shiftJson)
          : null,
    );
  }

  final String id;
  final String shiftId;
  final String requesterId;
  final String requesterName;
  final String? swapWithUserId;
  final String? swapWithName;
  final String? notes;
  final SwapRequestStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? decisionReason;
  final SwapShiftInfo? shift;
}

enum ScheduleRepositoryErrorType { offline, unknown }

class ScheduleRepositoryException implements Exception {
  const ScheduleRepositoryException._({
    required this.type,
    required this.message,
  });

  const ScheduleRepositoryException.offline()
    : this._(
        type: ScheduleRepositoryErrorType.offline,
        message: 'You are offline.',
      );

  const ScheduleRepositoryException.unknown([
    String message = 'Unable to load your schedule right now.',
  ]) : this._(
         type: ScheduleRepositoryErrorType.unknown,
         message: message,
       );

  final ScheduleRepositoryErrorType type;
  final String message;

  @override
  String toString() => 'ScheduleRepositoryException($type): $message';
}

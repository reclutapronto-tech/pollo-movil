class ClockActionResult {
  const ClockActionResult({
    required this.eventId,
    required this.occurredAt,
    this.queued = false,
  });

  final String eventId;
  final DateTime occurredAt;

  /// True when the event could not reach the server and was written to the
  /// local outbox (`pending_events`). `SyncEngine` will replay it when the
  /// device regains connectivity. Callers should treat this as a success for
  /// UI state but may want to surface an "offline, will sync later" hint.
  final bool queued;
}

abstract class ClockRepository {
  Future<ClockActionResult> clockIn({required String jobId});
  Future<ClockActionResult> clockOut({required String jobId});
  Future<ClockActionResult> breakStart({required String jobId});
  Future<ClockActionResult> breakEnd({required String jobId});
}

enum ClockRepositoryErrorType {
  offline,
  locationDenied,
  locationUnavailable,
  unknown,
}

class ClockRepositoryException implements Exception {
  const ClockRepositoryException._({
    required this.type,
    required this.message,
  });

  const ClockRepositoryException.offline()
    : this._(
        type: ClockRepositoryErrorType.offline,
        message: 'Connection is unavailable for clock events.',
      );

  const ClockRepositoryException.locationDenied()
    : this._(
        type: ClockRepositoryErrorType.locationDenied,
        message: 'Location permission is required before clocking in.',
      );

  const ClockRepositoryException.locationUnavailable()
    : this._(
        type: ClockRepositoryErrorType.locationUnavailable,
        message: 'Current location could not be captured.',
      );

  const ClockRepositoryException.unknown([
    String message = 'Clock in could not be completed right now.',
  ]) : this._(
         type: ClockRepositoryErrorType.unknown,
         message: message,
       );

  final ClockRepositoryErrorType type;
  final String message;

  @override
  String toString() => 'ClockRepositoryException($type): $message';
}

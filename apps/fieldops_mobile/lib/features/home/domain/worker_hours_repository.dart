import 'package:fieldops_mobile/features/home/domain/worker_hours_snapshot.dart';

abstract class WorkerHoursRepository {
  Future<WorkerHoursSnapshot> fetchSummary();
}

enum WorkerHoursRepositoryErrorType { offline, unknown }

class WorkerHoursRepositoryException implements Exception {
  const WorkerHoursRepositoryException._({
    required this.type,
    required this.message,
  });

  const WorkerHoursRepositoryException.offline()
    : this._(
        type: WorkerHoursRepositoryErrorType.offline,
        message: 'Connection is unavailable for worker hour totals.',
      );

  const WorkerHoursRepositoryException.unknown([
    String message = 'Worker hour totals are unavailable right now.',
  ]) : this._(type: WorkerHoursRepositoryErrorType.unknown, message: message);

  final WorkerHoursRepositoryErrorType type;
  final String message;

  @override
  String toString() => 'WorkerHoursRepositoryException($type): $message';
}

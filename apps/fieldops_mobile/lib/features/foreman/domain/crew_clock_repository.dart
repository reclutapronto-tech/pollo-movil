import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';

/// Foreman clocks in/out a worker on their behalf.
/// Creates an immutable audit trail showing who clocked whom.
abstract class CrewClockRepository {
  Future<ClockActionResult> clockInWorker({
    required String workerId,
    required String jobId,
  });

  Future<ClockActionResult> clockOutWorker({
    required String workerId,
    required String jobId,
  });
}

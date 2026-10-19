import 'package:fieldops_mobile/features/safety/domain/safety_checklist.dart';

abstract class SafetyRepository {
  /// Submits a completed safety checklist for a job.
  Future<String> submitChecklist({
    required String jobId,
    required List<SafetyChecklistResponse> responses,
  });

  /// Returns true if the worker has already completed today's checklist for
  /// the given job.
  Future<bool> hasCompletedToday(String jobId);
}

class SafetyRepositoryException implements Exception {
  const SafetyRepositoryException(this.message);
  final String message;

  @override
  String toString() => 'SafetyRepositoryException: $message';
}

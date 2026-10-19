import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';

abstract class JobsRepository {
  Future<List<JobSummary>> fetchActiveJobs();
}

enum JobsRepositoryErrorType { offline, unknown }

class JobsRepositoryException implements Exception {
  const JobsRepositoryException._({
    required this.type,
    required this.message,
  });

  const JobsRepositoryException.offline()
    : this._(
        type: JobsRepositoryErrorType.offline,
        message: 'You are offline',
      );

  const JobsRepositoryException.unknown([
    String message = 'Unable to load assigned jobs right now.',
  ]) : this._(
         type: JobsRepositoryErrorType.unknown,
         message: message,
       );

  final JobsRepositoryErrorType type;
  final String message;

  bool get isOffline => type == JobsRepositoryErrorType.offline;

  @override
  String toString() => 'JobsRepositoryException($type): $message';
}

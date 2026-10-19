import 'dart:io';

import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/jobs/domain/jobs_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseJobsRepository implements JobsRepository {
  const SupabaseJobsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<JobSummary>> fetchActiveJobs() async {
    try {
      final response = await _client.functions.invoke(
        'jobs_active',
        method: HttpMethod.get,
        headers: const {'X-Client-Version': 'fieldops-mobile'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const JobsRepositoryException.unknown(
          'Assigned jobs response was malformed.',
        );
      }

      final jobs = payload['jobs'] as List<dynamic>? ?? const [];
      return jobs
          .whereType<Map<String, dynamic>>()
          .map(JobSummary.fromJson)
          .toList(growable: false);
    } on SocketException {
      throw const JobsRepositoryException.offline();
    } on HttpException {
      throw const JobsRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const JobsRepositoryException.offline();
      }
      throw JobsRepositoryException.unknown(
        'Assigned jobs request failed (${error.status}).',
      );
    }
  }
}

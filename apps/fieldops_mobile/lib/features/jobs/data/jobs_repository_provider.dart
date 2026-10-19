import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/jobs/data/supabase_jobs_repository.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/jobs/domain/jobs_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final jobsRepositoryProvider = Provider<JobsRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredJobsRepository();
  }

  return SupabaseJobsRepository(Supabase.instance.client);
});

class _UnconfiguredJobsRepository implements JobsRepository {
  const _UnconfiguredJobsRepository();

  @override
  Future<List<JobSummary>> fetchActiveJobs() {
    throw const JobsRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }
}

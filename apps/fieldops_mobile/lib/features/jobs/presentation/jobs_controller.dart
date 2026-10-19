import 'package:fieldops_mobile/features/jobs/data/jobs_repository_provider.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final jobsControllerProvider =
    AsyncNotifierProvider<JobsController, List<JobSummary>>(
      JobsController.new,
    );

class JobsController extends AsyncNotifier<List<JobSummary>> {
  @override
  Future<List<JobSummary>> build() {
    return ref.watch(jobsRepositoryProvider).fetchActiveJobs();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(jobsRepositoryProvider).fetchActiveJobs(),
    );
  }
}

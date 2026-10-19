import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/home/data/supabase_worker_hours_repository.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_repository.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final workerHoursRepositoryProvider = Provider<WorkerHoursRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredWorkerHoursRepository();
  }

  return SupabaseWorkerHoursRepository(Supabase.instance.client);
});

class _UnconfiguredWorkerHoursRepository implements WorkerHoursRepository {
  const _UnconfiguredWorkerHoursRepository();

  @override
  Future<WorkerHoursSnapshot> fetchSummary() {
    throw const WorkerHoursRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }
}

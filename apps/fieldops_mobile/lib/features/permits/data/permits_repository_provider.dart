import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/permits/data/supabase_permits_repository.dart';
import 'package:fieldops_mobile/features/permits/domain/permits_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final permitsRepositoryProvider = Provider<PermitsRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredPermitsRepository();
  }
  return SupabasePermitsRepository(Supabase.instance.client);
});

class _UnconfiguredPermitsRepository implements PermitsRepository {
  const _UnconfiguredPermitsRepository();

  @override
  Future<PermitCheckResult> checkActive({required String jobId}) {
    throw const PermitsRepositoryException.unknown('not configured');
  }
}

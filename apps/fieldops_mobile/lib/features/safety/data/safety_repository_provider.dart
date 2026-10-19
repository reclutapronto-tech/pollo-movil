import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/safety/data/supabase_safety_repository.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_checklist.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredSafetyRepository();
  }
  return SupabaseSafetyRepository(Supabase.instance.client);
});

class _UnconfiguredSafetyRepository implements SafetyRepository {
  const _UnconfiguredSafetyRepository();

  @override
  Future<String> submitChecklist({
    required String jobId,
    required List<SafetyChecklistResponse> responses,
  }) {
    throw const SafetyRepositoryException('Missing Supabase configuration.');
  }

  @override
  Future<bool> hasCompletedToday(String jobId) async => false;
}

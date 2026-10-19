import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/overtime/data/supabase_ot_repository.dart';
import 'package:fieldops_mobile/features/overtime/domain/ot_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final otRepositoryProvider = Provider<OTRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredOTRepository();
  }
  return SupabaseOTRepository(Supabase.instance.client);
});

class _UnconfiguredOTRepository implements OTRepository {
  const _UnconfiguredOTRepository();

  @override
  Future<String> submitRequest({
    required String jobId,
    double? totalHours,
    String? notes,
    String? photoEventId,
  }) {
    throw const OTRepositoryException.unknown(
      'Missing Supabase configuration.',
    );
  }

  @override
  Future<List<OTRequest>> fetchPendingRequests() {
    throw const OTRepositoryException.unknown(
      'Missing Supabase configuration.',
    );
  }

  @override
  Future<void> approveRequest(String requestId) {
    throw const OTRepositoryException.unknown(
      'Missing Supabase configuration.',
    );
  }

  @override
  Future<void> denyRequest(String requestId, {String? reason}) {
    throw const OTRepositoryException.unknown(
      'Missing Supabase configuration.',
    );
  }
}

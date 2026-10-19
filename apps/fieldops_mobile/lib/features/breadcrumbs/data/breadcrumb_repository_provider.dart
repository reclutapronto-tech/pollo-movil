import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/breadcrumbs/data/supabase_breadcrumb_repository.dart';
import 'package:fieldops_mobile/features/breadcrumbs/domain/breadcrumb_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final breadcrumbRepositoryProvider = Provider<BreadcrumbRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredBreadcrumbRepository();
  }
  return SupabaseBreadcrumbRepository(Supabase.instance.client);
});

class _UnconfiguredBreadcrumbRepository implements BreadcrumbRepository {
  const _UnconfiguredBreadcrumbRepository();

  @override
  Future<List<Breadcrumb>> fetchBreadcrumbs({
    required String shiftDate,
    String? userId,
    String? jobId,
  }) {
    throw const BreadcrumbRepositoryException(
      'Breadcrumb service is not configured.',
    );
  }

  @override
  Future<void> uploadBreadcrumbs(List<Map<String, dynamic>> breadcrumbs) {
    throw const BreadcrumbRepositoryException(
      'Breadcrumb service is not configured.',
    );
  }
}

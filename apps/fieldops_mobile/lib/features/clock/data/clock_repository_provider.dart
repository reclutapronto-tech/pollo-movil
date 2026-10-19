import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/clock/data/supabase_clock_repository.dart';
import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final clockRepositoryProvider = Provider<ClockRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredClockRepository();
  }

  return SupabaseClockRepository(
    Supabase.instance.client,
    localDatabase: ref.watch(localDatabaseProvider),
  );
});

class _UnconfiguredClockRepository implements ClockRepository {
  const _UnconfiguredClockRepository();

  @override
  Future<ClockActionResult> clockIn({required String jobId}) {
    throw const ClockRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<ClockActionResult> clockOut({required String jobId}) {
    throw const ClockRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<ClockActionResult> breakStart({required String jobId}) {
    throw const ClockRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<ClockActionResult> breakEnd({required String jobId}) {
    throw const ClockRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }
}

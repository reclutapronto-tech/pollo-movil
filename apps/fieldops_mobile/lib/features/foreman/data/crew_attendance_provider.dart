import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/foreman/data/supabase_crew_attendance_repository.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_attendance_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final crewAttendanceRepositoryProvider =
    Provider<CrewAttendanceRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredCrewAttendanceRepository();
  }
  return SupabaseCrewAttendanceRepository(Supabase.instance.client);
});

class _UnconfiguredCrewAttendanceRepository
    implements CrewAttendanceRepository {
  const _UnconfiguredCrewAttendanceRepository();

  @override
  Future<List<CrewMemberStatus>> fetchCrewAttendance() {
    throw const CrewAttendanceException('Missing Supabase configuration.');
  }
}

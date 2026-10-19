import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/schedule/data/supabase_schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredScheduleRepository();
  }

  return SupabaseScheduleRepository(Supabase.instance.client);
});

class _UnconfiguredScheduleRepository implements ScheduleRepository {
  const _UnconfiguredScheduleRepository();

  @override
  Future<List<WorkerScheduleShift>> fetchMySchedule({
    DateTime? from,
    DateTime? to,
  }) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<String> requestShiftSwap({
    required String shiftId,
    String? notes,
  }) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<List<CrewScheduleShift>> fetchCrewSchedule({
    DateTime? from,
    DateTime? to,
  }) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<bool> saveCrewReorder(List<CrewScheduleShift> shifts) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<List<SwapRequest>> fetchSwapRequests({String status = 'pending'}) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<void> approveSwap(String swapRequestId, {String? reason}) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<void> denySwap(String swapRequestId, {required String reason}) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<void> cancelSwap(String swapRequestId) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<int> copyWeek({
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime targetStart,
  }) {
    throw const ScheduleRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }
}

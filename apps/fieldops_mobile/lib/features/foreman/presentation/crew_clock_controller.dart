import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_clock_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controller for foreman clocking crew members in/out.
/// Uses per-worker family so each tile tracks its own loading state.
class CrewClockController extends AsyncNotifier<ClockActionResult?> {
  // ignore: avoid_unused_constructor_parameters
  CrewClockController(String _);

  late final CrewClockRepository _repository;

  @override
  Future<ClockActionResult?> build() async {
    _repository = ref.watch(crewClockRepositoryProvider);
    return null;
  }

  /// Clock in a crew member
  Future<ClockActionResult> clockIn({
    required String workerId,
    required String jobId,
  }) async {
    state = const AsyncLoading();

    try {
      final result = await _repository.clockInWorker(
        workerId: workerId,
        jobId: jobId,
      );
      state = AsyncData(result);
      return result;
    } catch (e, stack) {
      state = AsyncError<ClockActionResult?>(e, stack);
      rethrow;
    }
  }

  /// Clock out a crew member
  Future<ClockActionResult> clockOut({
    required String workerId,
    required String jobId,
  }) async {
    state = const AsyncLoading();

    try {
      final result = await _repository.clockOutWorker(
        workerId: workerId,
        jobId: jobId,
      );
      state = AsyncData(result);
      return result;
    } catch (e, stack) {
      state = AsyncError<ClockActionResult?>(e, stack);
      rethrow;
    }
  }
}

final crewClockControllerProvider = AsyncNotifierProvider.family<
    CrewClockController, ClockActionResult?, String>(
  (arg) => CrewClockController(arg),
);

/// Provider for the crew clock repository implementation.
final crewClockRepositoryProvider = Provider<CrewClockRepository>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

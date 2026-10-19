import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/home/data/worker_hours_repository_provider.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final workerHoursControllerProvider =
    AsyncNotifierProvider<WorkerHoursController, WorkerHoursSnapshot>(
      WorkerHoursController.new,
    );

class WorkerHoursController extends AsyncNotifier<WorkerHoursSnapshot> {
  @override
  Future<WorkerHoursSnapshot> build() {
    ref.watch(
      clockControllerProvider.select(
        (state) => (
          lastOccurredAt: state.lastOccurredAt,
          activeJobId: state.activeJobId,
          isOnBreak: state.isOnBreak,
        ),
      ),
    );
    return ref.watch(workerHoursRepositoryProvider).fetchSummary();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(workerHoursRepositoryProvider).fetchSummary(),
    );
  }
}

import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final workerScheduleControllerProvider =
    AsyncNotifierProvider<WorkerScheduleController, List<WorkerScheduleShift>>(
      WorkerScheduleController.new,
    );

class WorkerScheduleController extends AsyncNotifier<List<WorkerScheduleShift>> {
  @override
  Future<List<WorkerScheduleShift>> build() {
    return ref.watch(scheduleRepositoryProvider).fetchMySchedule();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(scheduleRepositoryProvider).fetchMySchedule(),
    );
  }

  /// Called from `onReorderItem` (Flutter ≥3.41), which already adjusts
  /// `newIndex` for the removed-at-oldIndex slot — no manual `newIndex--`
  /// needed.
  Future<void> reorderShifts(int oldIndex, int newIndex) async {
    final currentShifts = state.value;
    if (currentShifts == null || currentShifts.length < 2) return;

    final updatedShifts = List<WorkerScheduleShift>.from(currentShifts);
    final movedShift = updatedShifts.removeAt(oldIndex);
    updatedShifts.insert(newIndex, movedShift);

    // Optimistically update UI
    state = AsyncData(updatedShifts);

    // Here we'd call the repository to bulk update / draft the rearranged shifts.
    // e.g. await ref.read(scheduleRepositoryProvider).updateShiftTimes(movedShift.id, ...);
  }
}

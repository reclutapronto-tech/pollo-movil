import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final foremanScheduleControllerProvider = AsyncNotifierProvider<
    ForemanScheduleController, ForemanScheduleState>(
  ForemanScheduleController.new,
);

class ForemanScheduleController
    extends AsyncNotifier<ForemanScheduleState> {
  @override
  Future<ForemanScheduleState> build() async {
    final shifts =
        await ref.watch(scheduleRepositoryProvider).fetchCrewSchedule();
    return ForemanScheduleState(shifts: shifts);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        final shifts =
            await ref.read(scheduleRepositoryProvider).fetchCrewSchedule();
        return ForemanScheduleState(shifts: shifts);
      },
    );
  }

  /// Reorders shifts locally after a drag gesture.
  /// Called from `onReorderItem` (Flutter ≥3.41), which hands back the
  /// post-removal `newIndex` directly — no manual `newIndex--` adjustment
  /// needed.
  void reorder(int oldIndex, int newIndex) {
    final current = state.value;
    if (current == null || current.shifts.length < 2) return;

    final updated = List<CrewScheduleShift>.from(current.shifts);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);

    // Re-number sort orders sequentially.
    final renumbered = <CrewScheduleShift>[
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(sortOrder: i),
    ];

    state = AsyncData(
      current.copyWith(shifts: renumbered, hasUnsavedChanges: true),
    );
  }

  /// Persists the current order to the backend.
  Future<bool> saveChanges() async {
    final current = state.value;
    if (current == null || !current.hasUnsavedChanges) return false;

    state = AsyncData(current.copyWith(isSaving: true));

    try {
      final success = await ref
          .read(scheduleRepositoryProvider)
          .saveCrewReorder(current.shifts);

      state = AsyncData(
        current.copyWith(
          hasUnsavedChanges: !success,
          isSaving: false,
        ),
      );
      return success;
    } on Exception {
      state = AsyncData(current.copyWith(isSaving: false));
      return false;
    }
  }
}

class ForemanScheduleState {
  const ForemanScheduleState({
    required this.shifts,
    this.hasUnsavedChanges = false,
    this.isSaving = false,
  });

  final List<CrewScheduleShift> shifts;
  final bool hasUnsavedChanges;
  final bool isSaving;

  ForemanScheduleState copyWith({
    List<CrewScheduleShift>? shifts,
    bool? hasUnsavedChanges,
    bool? isSaving,
  }) {
    return ForemanScheduleState(
      shifts: shifts ?? this.shifts,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

import 'package:fieldops_mobile/features/foreman/data/crew_attendance_provider.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_attendance_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final crewAttendanceProvider =
    AsyncNotifierProvider<CrewAttendanceController, List<CrewMemberStatus>>(
  CrewAttendanceController.new,
);

class CrewAttendanceController
    extends AsyncNotifier<List<CrewMemberStatus>> {
  @override
  Future<List<CrewMemberStatus>> build() {
    return ref.watch(crewAttendanceRepositoryProvider).fetchCrewAttendance();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(crewAttendanceRepositoryProvider).fetchCrewAttendance(),
    );
  }
}

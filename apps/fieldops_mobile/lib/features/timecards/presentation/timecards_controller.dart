import 'dart:typed_data';

import 'package:fieldops_mobile/features/timecards/data/timecard_repository_provider.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_signature.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final timecardsProvider =
    AsyncNotifierProvider<TimecardsController, List<TimecardPeriod>>(
  TimecardsController.new,
);

class TimecardsController extends AsyncNotifier<List<TimecardPeriod>> {
  @override
  Future<List<TimecardPeriod>> build() {
    return ref.watch(timecardRepositoryProvider).fetchMyTimecards();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(timecardRepositoryProvider).fetchMyTimecards(),
    );
  }

  Future<void> sign(String timecardId, {Uint8List? signatureImage}) async {
    await ref
        .read(timecardRepositoryProvider)
        .signTimecard(timecardId, signatureImage: signatureImage);
    // Reload to get updated signatures
    await reload();
  }
}

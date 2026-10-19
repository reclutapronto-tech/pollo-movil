import 'package:fieldops_mobile/features/history/data/history_repository_provider.dart';
import 'package:fieldops_mobile/features/history/domain/history_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final historyControllerProvider =
    AsyncNotifierProvider<HistoryController, List<HistoryEntry>>(
  HistoryController.new,
);

class HistoryController extends AsyncNotifier<List<HistoryEntry>> {
  @override
  Future<List<HistoryEntry>> build() {
    return ref.watch(historyRepositoryProvider).fetchHistory();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(historyRepositoryProvider).fetchHistory(),
    );
  }
}

/// Summary for "this week".
final weekSummaryProvider = FutureProvider<HistorySummary>((ref) {
  final now = DateTime.now();
  // Monday of current week
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final from = DateTime(monday.year, monday.month, monday.day);
  return ref.watch(historyRepositoryProvider).fetchSummary(from: from, to: now);
});

/// Summary for "this month".
final monthSummaryProvider = FutureProvider<HistorySummary>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month);
  return ref.watch(historyRepositoryProvider).fetchSummary(from: from, to: now);
});

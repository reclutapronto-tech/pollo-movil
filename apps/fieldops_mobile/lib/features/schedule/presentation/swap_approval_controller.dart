import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final swapApprovalProvider =
    AsyncNotifierProvider<SwapApprovalController, List<SwapRequest>>(
  SwapApprovalController.new,
);

class SwapApprovalController extends AsyncNotifier<List<SwapRequest>> {
  @override
  Future<List<SwapRequest>> build() {
    return ref.watch(scheduleRepositoryProvider).fetchSwapRequests();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(scheduleRepositoryProvider).fetchSwapRequests(),
    );
  }

  Future<void> approve(String swapRequestId, {String? reason}) async {
    await ref
        .read(scheduleRepositoryProvider)
        .approveSwap(swapRequestId, reason: reason);
    state = state.whenData(
      (requests) => requests.where((r) => r.id != swapRequestId).toList(),
    );
  }

  Future<void> deny(String swapRequestId, {required String reason}) async {
    await ref
        .read(scheduleRepositoryProvider)
        .denySwap(swapRequestId, reason: reason);
    state = state.whenData(
      (requests) => requests.where((r) => r.id != swapRequestId).toList(),
    );
  }
}

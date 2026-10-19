import 'package:fieldops_mobile/features/overtime/data/ot_repository_provider.dart';
import 'package:fieldops_mobile/features/overtime/domain/ot_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final otApprovalProvider =
    AsyncNotifierProvider<OTApprovalController, List<OTRequest>>(
  OTApprovalController.new,
);

class OTApprovalController extends AsyncNotifier<List<OTRequest>> {
  @override
  Future<List<OTRequest>> build() {
    return ref.watch(otRepositoryProvider).fetchPendingRequests();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(otRepositoryProvider).fetchPendingRequests(),
    );
  }

  Future<void> approve(String requestId) async {
    await ref.read(otRepositoryProvider).approveRequest(requestId);
    // Optimistically remove from the list
    state = state.whenData(
      (requests) => requests.where((r) => r.id != requestId).toList(),
    );
  }

  Future<void> deny(String requestId, {String? reason}) async {
    await ref.read(otRepositoryProvider).denyRequest(requestId, reason: reason);
    state = state.whenData(
      (requests) => requests.where((r) => r.id != requestId).toList(),
    );
  }
}

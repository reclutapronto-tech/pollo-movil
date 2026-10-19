import 'package:fieldops_mobile/features/pto/data/supabase_pto_repository.dart';
import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ptoApprovalProvider =
    AsyncNotifierProvider<PTOApprovalController, List<PTORequest>>(
  PTOApprovalController.new,
);

class PTOApprovalController extends AsyncNotifier<List<PTORequest>> {
  @override
  Future<List<PTORequest>> build() {
    return ref.watch(ptoRepositoryProvider).fetchPendingApprovals();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(ptoRepositoryProvider).fetchPendingApprovals(),
    );
  }

  Future<void> approve(String requestId) async {
    await ref.read(ptoRepositoryProvider).approveRequest(requestId);
    state = state.whenData(
      (requests) => requests.where((r) => r.id != requestId).toList(),
    );
  }

  Future<void> deny(String requestId, {String? reason}) async {
    await ref.read(ptoRepositoryProvider).denyRequest(requestId, reason: reason);
    state = state.whenData(
      (requests) => requests.where((r) => r.id != requestId).toList(),
    );
  }
}

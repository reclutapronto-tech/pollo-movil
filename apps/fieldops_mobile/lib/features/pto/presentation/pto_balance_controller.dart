import 'package:fieldops_mobile/features/pto/data/supabase_pto_repository.dart';
import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ptoBalanceProvider =
    AsyncNotifierProvider<PTOBalanceController, PTOBalance>(
  PTOBalanceController.new,
);

class PTOBalanceController extends AsyncNotifier<PTOBalance> {
  @override
  Future<PTOBalance> build() {
    return ref.watch(ptoRepositoryProvider).fetchMyBalance();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(ptoRepositoryProvider).fetchMyBalance(),
    );
  }
}

import 'package:fieldops_mobile/features/pto/data/supabase_pto_repository.dart';
import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ptoListProvider = FutureProvider<List<PTORequest>>((ref) async {
  final repo = ref.watch(ptoRepositoryProvider);
  return repo.fetchMyRequests();
});

final ptoControllerProvider =
    NotifierProvider<PTOController, PTOControllerState>(PTOController.new);

class PTOController extends Notifier<PTOControllerState> {
  @override
  PTOControllerState build() => const PTOControllerState();

  Future<void> submit({
    required String type,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final repo = ref.read(ptoRepositoryProvider);
      await repo.submitRequest(
        type: type,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
      );
      state = state.copyWith(isSubmitting: false, submitted: true);
      ref.invalidate(ptoListProvider);
    } on PTORepositoryException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
    } on Exception catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Could not submit request. Try again.',
      );
    }
  }

  void reset() {
    state = const PTOControllerState();
  }
}

class PTOControllerState {
  const PTOControllerState({
    this.isSubmitting = false,
    this.submitted = false,
    this.error,
  });

  final bool isSubmitting;
  final bool submitted;
  final String? error;

  PTOControllerState copyWith({
    bool? isSubmitting,
    bool? submitted,
    String? error,
  }) {
    return PTOControllerState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitted: submitted ?? this.submitted,
      error: error,
    );
  }
}

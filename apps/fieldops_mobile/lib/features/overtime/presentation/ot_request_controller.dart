import 'package:fieldops_mobile/features/overtime/data/ot_repository_provider.dart';
import 'package:fieldops_mobile/features/overtime/domain/ot_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final otRequestControllerProvider =
    NotifierProvider<OTRequestController, OTRequestState>(
  OTRequestController.new,
);

class OTRequestController extends Notifier<OTRequestState> {
  @override
  OTRequestState build() => const OTRequestState();

  Future<void> submit({
    required String jobId,
    double? totalHours,
    String? notes,
    String? photoEventId,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null, successId: null);

    try {
      final requestId = await ref.read(otRepositoryProvider).submitRequest(
            jobId: jobId,
            totalHours: totalHours,
            notes: notes,
            photoEventId: photoEventId,
          );
      state = state.copyWith(isSubmitting: false, successId: requestId);
    } on OTRepositoryException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
    } on Exception catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'OT request could not be submitted.',
      );
    }
  }

  void reset() {
    state = const OTRequestState();
  }
}

class OTRequestState {
  const OTRequestState({
    this.isSubmitting = false,
    this.error,
    this.successId,
  });

  final bool isSubmitting;
  final String? error;
  final String? successId;

  bool get isSuccess => successId != null;

  OTRequestState copyWith({
    bool? isSubmitting,
    Object? error = _otSentinel,
    Object? successId = _otSentinel,
  }) {
    return OTRequestState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error == _otSentinel ? this.error : error as String?,
      successId: successId == _otSentinel ? this.successId : successId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OTRequestState &&
          isSubmitting == other.isSubmitting &&
          error == other.error &&
          successId == other.successId;

  @override
  int get hashCode => Object.hash(isSubmitting, error, successId);
}

const _otSentinel = Object();

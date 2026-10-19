import 'package:fieldops_mobile/features/safety/data/safety_repository_provider.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_checklist.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final safetyChecklistControllerProvider =
    NotifierProvider<SafetyChecklistController, SafetyChecklistState>(
  SafetyChecklistController.new,
);

class SafetyChecklistController extends Notifier<SafetyChecklistState> {
  @override
  SafetyChecklistState build() => const SafetyChecklistState();

  void answerQuestion(String questionId, {required bool answer}) {
    final now = DateTime.now();
    final updated = Map<String, SafetyChecklistResponse>.from(state.answers);
    updated[questionId] = SafetyChecklistResponse(
      questionId: questionId,
      answer: answer,
      answeredAt: now,
    );
    state = state.copyWith(answers: updated);
  }

  Future<void> submit({required String jobId}) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final checklistId =
          await ref.read(safetyRepositoryProvider).submitChecklist(
                jobId: jobId,
                responses: state.answers.values.toList(),
              );
      state = state.copyWith(
        isSubmitting: false,
        submittedId: checklistId,
      );
    } on SafetyRepositoryException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
    } on Exception catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Could not submit safety checklist.',
      );
    }
  }

  void reset() {
    state = const SafetyChecklistState();
  }
}

class SafetyChecklistState {
  const SafetyChecklistState({
    this.answers = const {},
    this.isSubmitting = false,
    this.submittedId,
    this.error,
  });

  final Map<String, SafetyChecklistResponse> answers;
  final bool isSubmitting;
  final String? submittedId;
  final String? error;

  bool get isSubmitted => submittedId != null;

  bool isAllAnswered(List<SafetyQuestion> questions) {
    for (final q in questions) {
      if (q.required && !answers.containsKey(q.id)) return false;
    }
    return true;
  }

  bool hasFlaggedItems() {
    return answers.values.any((r) => !r.answer);
  }

  SafetyChecklistState copyWith({
    Map<String, SafetyChecklistResponse>? answers,
    bool? isSubmitting,
    Object? submittedId = _sentinel,
    Object? error = _sentinel,
  }) {
    return SafetyChecklistState(
      answers: answers ?? this.answers,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submittedId:
          submittedId == _sentinel ? this.submittedId : submittedId as String?,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

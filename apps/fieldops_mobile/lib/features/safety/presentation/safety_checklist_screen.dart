import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_checklist.dart';
import 'package:fieldops_mobile/features/safety/presentation/safety_checklist_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pre-shift safety sign-off checklist.
///
/// Workers must answer all required questions before starting work.
/// Flagged items (answer == false) are highlighted and still submittable
/// so that the audit trail captures safety concerns.
class SafetyChecklistScreen extends ConsumerWidget {
  const SafetyChecklistScreen({
    super.key,
    required this.jobId,
    required this.jobName,
  });

  final String jobId;
  final String jobName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(safetyChecklistControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    const questions = defaultSafetyQuestions;

    ref.listen(safetyChecklistControllerProvider, (_, next) {
      if (next.isSubmitted && context.mounted) {
        ref.read(safetyChecklistControllerProvider.notifier).reset();
        Navigator.of(context).pop(true);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Checklist'),
        leading: const BackButton(),
      ),
      body: Column(
        children: [
          // Job context header
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.muted,
              borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_rounded, color: palette.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pre-Shift Safety Sign-Off',
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        jobName,
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.steel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Questions
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final q = questions[index];
                final response = state.answers[q.id];
                return _SafetyQuestionCard(
                  question: q,
                  response: response,
                  index: index + 1,
                  onAnswer: (answer) {
                    ref
                        .read(safetyChecklistControllerProvider.notifier)
                        .answerQuestion(q.id, answer: answer);
                  },
                );
              },
            ),
          ),

          // Bottom bar with submit
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surfaceWhite,
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flagged warning
                if (state.hasFlaggedItems()) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: palette.signal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(FieldOpsRadius.md),
                      border: Border.all(
                        color: palette.signal.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: palette.signal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You flagged safety concerns. Your responses '
                            'will be logged for review.',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.signal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Error
                if (state.error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: palette.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(FieldOpsRadius.md),
                    ),
                    child: Text(
                      state.error!,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.danger,
                      ),
                    ),
                  ),
                ],

                // Submit
                Semantics(
                  button: true,
                  label: state.isSubmitting
                      ? 'Submitting safety checklist'
                      : 'Submit safety checklist',
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: state.isAllAnswered(questions) &&
                              !state.isSubmitting
                          ? () async {
                              await HapticFeedback.mediumImpact();
                              await ref
                                  .read(safetyChecklistControllerProvider
                                      .notifier)
                                  .submit(jobId: jobId);
                            }
                          : null,
                      icon: state.isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded),
                      label: Text(
                        state.isSubmitting
                            ? 'Submitting...'
                            : 'Confirm & Start Shift',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Question Card ────────────────────────────────────────────

class _SafetyQuestionCard extends StatelessWidget {
  const _SafetyQuestionCard({
    required this.question,
    required this.response,
    required this.index,
    required this.onAnswer,
  });

  final SafetyQuestion question;
  final SafetyChecklistResponse? response;
  final int index;
  final void Function(bool) onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final isAnswered = response != null;
    final isConfirmed = response?.answer ?? false;
    final borderColor = !isAnswered
        ? palette.border
        : isConfirmed
            ? palette.success.withValues(alpha: 0.4)
            : palette.danger.withValues(alpha: 0.4);
    final bgColor = !isAnswered
        ? palette.surfaceWhite
        : isConfirmed
            ? palette.success.withValues(alpha: 0.04)
            : palette.danger.withValues(alpha: 0.04);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.muted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$index',
                  style: textTheme.labelLarge?.copyWith(color: palette.steel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question.question,
                  style: textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Yes, confirm: ${question.question}',
                  child: _AnswerButton(
                    label: 'Yes',
                    icon: Icons.check_rounded,
                    isSelected: isAnswered && isConfirmed,
                    color: palette.success,
                    onPressed: () => onAnswer(true),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'No, flag concern: ${question.question}',
                  child: _AnswerButton(
                    label: 'No / Flag',
                    icon: Icons.flag_rounded,
                    isSelected: isAnswered && !isConfirmed,
                    color: palette.danger,
                    onPressed: () => onAnswer(false),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (isSelected) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(44),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: palette.steel),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.steel,
        side: BorderSide(color: palette.border),
        minimumSize: const Size.fromHeight(44),
      ),
    );
  }
}

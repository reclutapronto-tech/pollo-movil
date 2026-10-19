import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_request_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OTRequestScreen extends ConsumerStatefulWidget {
  const OTRequestScreen({
    super.key,
    required this.jobId,
    required this.jobName,
  });

  final String jobId;
  final String jobName;

  @override
  ConsumerState<OTRequestScreen> createState() => _OTRequestScreenState();
}

class _OTRequestScreenState extends ConsumerState<OTRequestScreen> {
  final _hoursController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _hoursController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final hours = double.tryParse(_hoursController.text);

    await ref.read(otRequestControllerProvider.notifier).submit(
          jobId: widget.jobId,
          totalHours: hours,
          notes: _notesController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(otRequestControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    ref.listen(otRequestControllerProvider, (_, next) {
      if (next.isSuccess && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OT request submitted')),
        );
        ref.read(otRequestControllerProvider.notifier).reset();
        Navigator.of(context).pop(true);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Overtime'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.muted,
                borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.work_history_rounded,
                    color: palette.signal,
                    semanticLabel: 'Job',
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.jobName, style: textTheme.titleLarge),
                      Text(
                        'Overtime request for this job',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Hours field
            Text('Hours worked so far', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Semantics(
              label: 'Total hours worked',
              textField: true,
              child: TextFormField(
                controller: _hoursController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'e.g. 9.5',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Notes field
            Text('Reason for overtime', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Semantics(
              label: 'Overtime reason',
              textField: true,
              child: TextFormField(
                controller: _notesController,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Explain why overtime is needed...',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(Icons.notes_rounded),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Error
            if (state.error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                  border: Border.all(
                    color: palette.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  state.error!,
                  style:
                      textTheme.bodyMedium?.copyWith(color: palette.danger),
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),

            // Submit
            Semantics(
              button: true,
              label: state.isSubmitting
                  ? 'Submitting overtime request'
                  : 'Submit overtime request',
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: state.isSubmitting ? null : _submit,
                  icon: state.isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    state.isSubmitting
                        ? 'Submitting...'
                        : 'Submit OT Request',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

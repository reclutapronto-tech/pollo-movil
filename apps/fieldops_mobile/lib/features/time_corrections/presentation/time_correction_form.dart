import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/time_corrections/data/time_correction_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Bottom-sheet form for submitting a time correction request.
class TimeCorrectionForm extends ConsumerStatefulWidget {
  const TimeCorrectionForm({
    super.key,
    this.workerId,
    this.jobId,
  });

  /// Pre-fill worker ID (supervisor flow). If null, current user is assumed.
  final String? workerId;
  final String? jobId;

  @override
  ConsumerState<TimeCorrectionForm> createState() => _TimeCorrectionFormState();
}

class _TimeCorrectionFormState extends ConsumerState<TimeCorrectionForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _evidenceController = TextEditingController();

  DateTime _correctedTime = DateTime.now();
  String _eventSubtype = 'clock_in';
  bool _isSubmitting = false;

  static const _subtypes = ['clock_in', 'clock_out', 'break_start', 'break_end'];

  @override
  void dispose() {
    _reasonController.dispose();
    _evidenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final repository = ref.read(timeCorrectionRepositoryProvider);
      await repository.createCorrection(
        workerId: widget.workerId ?? '',
        jobId: widget.jobId ?? '',
        correctedEventSubtype: _eventSubtype,
        correctedOccurredAt: _correctedTime,
        reason: _reasonController.text.trim(),
        evidenceNotes: _evidenceController.text.trim().isEmpty
            ? null
            : _evidenceController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correction submitted for review')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _correctedTime,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_correctedTime),
    );
    if (time == null) return;

    setState(() {
      _correctedTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, y — h:mm a');

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text('New Time Correction', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Request a correction to a clock event. '
              'A supervisor will review and approve.',
              style: textTheme.bodySmall?.copyWith(color: palette.steel),
            ),
            const SizedBox(height: 20),

            // Event type
            Text('Event Type', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _eventSubtype,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _subtypes
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.replaceAll('_', ' ').toUpperCase()),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _eventSubtype = v!),
            ),
            const SizedBox(height: 16),

            // Corrected time
            Text('Corrected Time', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: palette.steel),
                    const SizedBox(width: 8),
                    Text(dateFormat.format(_correctedTime)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Reason
            Text('Reason', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                hintText: 'Why does this time need correction?',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Reason is required' : null,
            ),
            const SizedBox(height: 16),

            // Evidence notes (optional)
            Text('Evidence Notes (optional)', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _evidenceController,
              decoration: const InputDecoration(
                hintText: 'Supervisor confirmation, photo ID, etc.',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Correction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

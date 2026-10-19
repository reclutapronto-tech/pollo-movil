import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom-sheet shown when worker clocks out.
///
/// Displays a shift duration summary (total elapsed time) and collects
/// an optional quick survey (tasks completed, issues, materials) that
/// feeds into daily shift reports.
class ShiftWrapupDialog extends StatefulWidget {
  const ShiftWrapupDialog({
    super.key,
    required this.jobName,
    this.clockedInAt,
  });

  final String jobName;

  /// When the shift started. If provided, total elapsed time is shown.
  final DateTime? clockedInAt;

  static Future<ShiftWrapupData?> show(
    BuildContext context, {
    required String jobName,
    DateTime? clockedInAt,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<ShiftWrapupData>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ShiftWrapupDialog(
        jobName: jobName,
        clockedInAt: clockedInAt,
      ),
    );
  }

  @override
  State<ShiftWrapupDialog> createState() => _ShiftWrapupDialogState();
}

class _ShiftWrapupDialogState extends State<ShiftWrapupDialog> {
  final _tasksController = TextEditingController();
  final _issuesController = TextEditingController();
  final _materialsController = TextEditingController();

  @override
  void dispose() {
    _tasksController.dispose();
    _issuesController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayHour:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now().toUtc();
    final elapsed = widget.clockedInAt != null
        ? now.difference(widget.clockedInAt!)
        : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Shift wrap-up', style: textTheme.titleLarge),
          Text(
            widget.jobName,
            style: textTheme.bodySmall?.copyWith(color: palette.steel),
          ),
          const SizedBox(height: 16),

          // --- Shift summary card ---
          if (elapsed != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                border: Border.all(
                  color: palette.success.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_rounded,
                    color: palette.success,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDuration(elapsed),
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Started ${_formatTime(widget.clockedInAt!)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.steel,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (elapsed != null) const SizedBox(height: 20),

          // --- Survey fields ---
          _buildField(
            context,
            'What did you complete today?',
            _tasksController,
          ),
          const SizedBox(height: 12),
          _buildField(
            context,
            'Any issues or blockers?',
            _issuesController,
          ),
          const SizedBox(height: 12),
          _buildField(
            context,
            'Materials used?',
            _materialsController,
          ),
          const SizedBox(height: 20),

          // --- Actions ---
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    const ShiftWrapupData(skipped: true),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.pop(
                      context,
                      ShiftWrapupData(
                        tasksCompleted: _tasksController.text,
                        issues: _issuesController.text,
                        materialsUsed: _materialsController.text,
                      ),
                    );
                  },
                  child: const Text('Submit & Clock Out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    BuildContext context,
    String label,
    TextEditingController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Optional',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FieldOpsRadius.md),
            ),
          ),
        ),
      ],
    );
  }
}

class ShiftWrapupData {
  const ShiftWrapupData({
    this.tasksCompleted = '',
    this.issues = '',
    this.materialsUsed = '',
    this.skipped = false,
  });

  final String tasksCompleted;
  final String issues;
  final String materialsUsed;
  final bool skipped;

  bool get isEmpty =>
      tasksCompleted.isEmpty && issues.isEmpty && materialsUsed.isEmpty;
}

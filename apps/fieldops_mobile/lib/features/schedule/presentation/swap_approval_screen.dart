import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/presentation/swap_approval_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SwapApprovalScreen extends ConsumerWidget {
  const SwapApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(swapApprovalProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swap Approvals'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(swapApprovalProvider.notifier).reload(),
        child: state.when(
          data: (requests) {
            if (requests.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 120),
                  _EmptyState(palette: palette, textTheme: textTheme),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _SwapCard(request: requests[index]),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 4),
          ),
          error: (error, _) {
            final message = error is ScheduleRepositoryException
                ? error.message
                : 'Could not load swap requests.';
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 120),
                _ErrorState(message: message, textTheme: textTheme),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Swap Card ──────────────────────────────────────────────

class _SwapCard extends ConsumerStatefulWidget {
  const _SwapCard({required this.request});

  final SwapRequest request;

  @override
  ConsumerState<_SwapCard> createState() => _SwapCardState();
}

class _SwapCardState extends ConsumerState<_SwapCard> {
  bool _isActing = false;

  Future<void> _approve() async {
    setState(() => _isActing = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref.read(swapApprovalProvider.notifier).approve(widget.request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Approved swap for ${widget.request.requesterName}',
            ),
          ),
        );
      }
    } on ScheduleRepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _deny() async {
    final reason = await _DenyReasonSheet.show(context);
    if (reason == null || reason.isEmpty) return;

    setState(() => _isActing = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(swapApprovalProvider.notifier)
          .deny(widget.request.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Denied swap for ${widget.request.requesterName}'),
          ),
        );
      }
    } on ScheduleRepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final req = widget.request;
    final shift = req.shift;
    final shiftSummary = shift == null
        ? 'Shift details unavailable'
        : '${_weekdayMonthDay(shift.shiftDate)} · ${shift.startTime}–${shift.endTime}';
    final target = req.swapWithName ?? 'Open to any worker';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.signal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.swap_horiz_rounded,
                    size: 22, color: palette.signal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req.requesterName, style: textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Wants to swap with: $target',
                      style: textTheme.bodySmall
                          ?.copyWith(color: palette.steel),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.muted,
              borderRadius: BorderRadius.circular(FieldOpsRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_rounded, size: 16, color: palette.steel),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shiftSummary, style: textTheme.bodyMedium),
                      if (shift != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          shift.jobName,
                          style: textTheme.bodySmall
                              ?.copyWith(color: palette.steel),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (req.notes != null && req.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.muted,
                borderRadius: BorderRadius.circular(FieldOpsRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_rounded, size: 16, color: palette.steel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(req.notes!, style: textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Deny swap for ${req.requesterName}',
                  child: OutlinedButton.icon(
                    onPressed: _isActing ? null : _deny,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Deny'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.danger,
                      side: BorderSide(
                        color: palette.danger.withValues(alpha: 0.4),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Approve swap for ${req.requesterName}',
                  child: ElevatedButton.icon(
                    onPressed: _isActing ? null : _approve,
                    icon: _isActing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.success,
                      minimumSize: const Size.fromHeight(44),
                    ),
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

String _weekdayMonthDay(DateTime d) {
  const weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
  final mo = months[(d.month - 1).clamp(0, 11)];
  return '$wd $mo ${d.day}';
}

// ─── Deny Reason Sheet ────────────────────────────────────────

class _DenyReasonSheet extends StatefulWidget {
  const _DenyReasonSheet();

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DenyReasonSheet(),
    );
  }

  @override
  State<_DenyReasonSheet> createState() => _DenyReasonSheetState();
}

class _DenyReasonSheetState extends State<_DenyReasonSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reason for denial',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Required — shared with the worker.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.steel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'e.g. schedule already confirmed',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final value = _controller.text.trim();
                    if (value.isEmpty) return;
                    Navigator.of(context).pop(value);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.danger,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Submit denial'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty / Error States ──────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.textTheme});

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.swap_horiz_rounded, size: 64, color: palette.steel),
        const SizedBox(height: 12),
        Text('No pending swap requests', style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Workers will appear here when they request to swap shifts.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: palette.steel),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.textTheme});

  final String message;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: textTheme.bodyMedium),
      ],
    );
  }
}

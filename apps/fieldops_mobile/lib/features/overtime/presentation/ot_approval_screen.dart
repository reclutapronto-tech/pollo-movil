import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/overtime/domain/ot_repository.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_approval_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OTApprovalScreen extends ConsumerWidget {
  const OTApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvalState = ref.watch(otApprovalProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OT Approvals'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(otApprovalProvider.notifier).reload(),
        child: approvalState.when(
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
              itemBuilder: (context, index) => _OTRequestCard(
                request: requests[index],
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 4),
          ),
          error: (error, _) {
            final message = error is OTRepositoryException
                ? error.message
                : 'Could not load OT requests.';
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

// ─── OT Request Card ──────────────────────────────────────────

class _OTRequestCard extends ConsumerStatefulWidget {
  const _OTRequestCard({required this.request});

  final OTRequest request;

  @override
  ConsumerState<_OTRequestCard> createState() => _OTRequestCardState();
}

class _OTRequestCardState extends ConsumerState<_OTRequestCard> {
  bool _isActing = false;

  Future<void> _approve() async {
    setState(() => _isActing = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(otApprovalProvider.notifier)
          .approve(widget.request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Approved OT for ${widget.request.workerName}',
            ),
          ),
        );
      }
    } on OTRepositoryException catch (e) {
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
    final reason = await _DenyReasonDialog.show(context);
    if (reason == null) return; // User cancelled

    setState(() => _isActing = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(otApprovalProvider.notifier)
          .deny(widget.request.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Denied OT for ${widget.request.workerName}',
            ),
          ),
        );
      }
    } on OTRepositoryException catch (e) {
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
    final hoursStr = req.totalHours != null
        ? '${req.totalHours!.toStringAsFixed(1)}h worked'
        : 'Hours not specified';
    final date = req.createdAt;
    final dateStr = '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

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
          // Header row: worker name + time
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.signal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.more_time_rounded,
                  size: 22,
                  color: palette.signal,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req.workerName, style: textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      '${req.jobName} \u00B7 $dateStr',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.steel,
                      ),
                    ),
                  ],
                ),
              ),
              // Hours badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.signal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                ),
                child: Text(
                  hoursStr,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.signal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // Notes (if any)
          if (req.notes != null && req.notes!.isNotEmpty) ...[
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
                  Icon(Icons.notes_rounded, size: 16, color: palette.steel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      req.notes!,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Deny overtime for ${req.workerName}',
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
                  label: 'Approve overtime for ${req.workerName}',
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

// ─── Deny Reason Dialog ───────────────────────────────────────

class _DenyReasonDialog extends StatefulWidget {
  const _DenyReasonDialog();

  /// Returns the denial reason, or `null` if the user cancelled.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DenyReasonDialog(),
    );
  }

  @override
  State<_DenyReasonDialog> createState() => _DenyReasonDialogState();
}

class _DenyReasonDialogState extends State<_DenyReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 20 + bottomInset),
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
          const SizedBox(height: 20),
          Text('Deny OT Request', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Provide an optional reason for the denial.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controller,
            maxLines: 3,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Reason (optional)...',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 48),
                child: Icon(Icons.notes_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_controller.text),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Deny'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.danger,
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

// ─── Empty & Error States ─────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.textTheme});

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.check_circle_outline_rounded,
          size: 48,
          color: palette.success.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Text('All caught up', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'No pending overtime requests to review.',
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
        Icon(
          Icons.wifi_off_rounded,
          size: 48,
          color: Colors.black.withValues(alpha: 0.32),
        ),
        const SizedBox(height: 12),
        Text('OT requests unavailable', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

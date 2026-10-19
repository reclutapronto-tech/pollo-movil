import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:fieldops_mobile/features/pto/presentation/pto_approval_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PTOApprovalScreen extends ConsumerWidget {
  const PTOApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ptoApprovalProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PTO Approvals'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ptoApprovalProvider.notifier).reload(),
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
                  _PTOApprovalCard(request: requests[index]),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 4),
          ),
          error: (error, _) {
            final message = error is PTORepositoryException
                ? error.message
                : 'Could not load PTO requests.';
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

// ─── PTO Approval Card ────────────────────────────────────────

class _PTOApprovalCard extends ConsumerStatefulWidget {
  const _PTOApprovalCard({required this.request});

  final PTORequest request;

  @override
  ConsumerState<_PTOApprovalCard> createState() => _PTOApprovalCardState();
}

class _PTOApprovalCardState extends ConsumerState<_PTOApprovalCard> {
  bool _isActing = false;

  static const _typeIcons = <String, IconData>{
    'vacation': Icons.beach_access_rounded,
    'sick': Icons.local_hospital_rounded,
    'personal': Icons.person_rounded,
  };

  static const _typeColors = <String, Color>{
    'vacation': Color(0xFF2563EB), // Blue
    'sick': Color(0xFFDC2626), // Red
    'personal': Color(0xFF7C3AED), // Purple
  };

  Future<void> _approve() async {
    setState(() => _isActing = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref.read(ptoApprovalProvider.notifier).approve(widget.request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Approved PTO for ${widget.request.workerName ?? 'worker'}',
            ),
          ),
        );
      }
    } on PTORepositoryException catch (e) {
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
    if (reason == null) return;

    setState(() => _isActing = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(ptoApprovalProvider.notifier)
          .deny(widget.request.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Denied PTO for ${widget.request.workerName ?? 'worker'}',
            ),
          ),
        );
      }
    } on PTORepositoryException catch (e) {
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
    final typeLabel = req.type[0].toUpperCase() + req.type.substring(1);
    final icon = _typeIcons[req.type] ?? Icons.event_rounded;
    final typeColor = _typeColors[req.type] ?? palette.signal;
    final dateRange =
        '${req.startDate.month}/${req.startDate.day} \u2013 ${req.endDate.month}/${req.endDate.day}';

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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: typeColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.workerName ?? 'Worker',
                      style: textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$typeLabel \u00B7 $dateRange \u00B7 ${req.dayCount}d',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.steel,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                ),
                child: Text(
                  typeLabel,
                  style: textTheme.labelSmall?.copyWith(
                    color: typeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // Notes
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
                    child: Text(req.notes!, style: textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Actions
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Deny PTO for ${req.workerName ?? 'worker'}',
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
                  label: 'Approve PTO for ${req.workerName ?? 'worker'}',
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
          Text('Deny PTO Request', style: textTheme.titleLarge),
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
                  onPressed: () => Navigator.of(context).pop(_controller.text),
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
          'No pending time off requests to review.',
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
        Text('PTO requests unavailable', style: textTheme.titleLarge),
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

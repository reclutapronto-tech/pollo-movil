import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/time_corrections/data/time_correction_repository_provider.dart';
import 'package:fieldops_mobile/features/time_corrections/domain/time_correction_repository.dart';
import 'package:fieldops_mobile/features/time_corrections/presentation/time_correction_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Screen for supervisors to view and manage time corrections.
class TimeCorrectionScreen extends ConsumerWidget {
  const TimeCorrectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(_pendingCorrectionsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Time Corrections'),
          leading: const BackButton(),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Denied'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CorrectionsList(
              correctionsAsync: pendingAsync,
              status: CorrectionStatus.pending,
            ),
            _CorrectionsList(
              correctionsAsync: ref.watch(_approvedCorrectionsProvider),
              status: CorrectionStatus.approved,
            ),
            _CorrectionsList(
              correctionsAsync: ref.watch(_deniedCorrectionsProvider),
              status: CorrectionStatus.denied,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCreateDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('New Correction'),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TimeCorrectionForm(),
    );
  }
}

class _CorrectionsList extends ConsumerWidget {
  const _CorrectionsList({
    required this.correctionsAsync,
    required this.status,
  });

  final AsyncValue<List<TimeCorrection>> correctionsAsync;
  final CorrectionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;

    return correctionsAsync.when(
      data: (corrections) {
        if (corrections.isEmpty) {
          return _EmptyState(status: status, palette: palette, textTheme: textTheme);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_correctionsProvider(status.label.toLowerCase())),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: corrections.length,
            itemBuilder: (context, index) => _CorrectionCard(
              correction: corrections[index],
              onAction: () => ref.invalidate(_correctionsProvider('pending')),
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: SkeletonLoader(itemCount: 3),
      ),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: palette.danger),
            const SizedBox(height: 12),
            Text('Failed to load', style: textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({
    required this.correction,
    required this.onAction,
  });

  final TimeCorrection correction;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, h:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    correction.workerName,
                    style: textTheme.titleSmall,
                  ),
                  Text(
                    correction.jobName,
                    style: textTheme.bodySmall?.copyWith(color: palette.steel),
                  ),
                ],
              ),
            ),
            _StatusBadge(status: correction.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Created ${dateFormat.format(correction.createdAt)}',
            style: textTheme.bodySmall?.copyWith(color: palette.steel),
          ),
        ),
        children: [
          const Divider(),
          const SizedBox(height: 8),

          // Correction details
          _DetailRow(
            label: 'New Time',
            value: dateFormat.format(correction.correctedOccurredAt),
            valueColor: palette.success,
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 8),

          if (correction.originalOccurredAt != null) ...[
            _DetailRow(
              label: 'Original Time',
              value: dateFormat.format(correction.originalOccurredAt!),
              valueColor: palette.steel,
              palette: palette,
              textTheme: textTheme,
            ),
            const SizedBox(height: 8),
          ],

          _DetailRow(
            label: 'Reason',
            value: correction.reason,
            palette: palette,
            textTheme: textTheme,
          ),

          if (correction.evidenceNotes != null) ...[
            const SizedBox(height: 8),
            _DetailRow(
              label: 'Evidence',
              value: correction.evidenceNotes!,
              palette: palette,
              textTheme: textTheme,
            ),
          ],

          if (correction.status == CorrectionStatus.pending) ...[
            const SizedBox(height: 16),
            _ActionButtons(
              correction: correction,
              onAction: onAction,
            ),
          ],

          if (correction.status != CorrectionStatus.pending &&
              correction.decidedByName != null) ...[
            const SizedBox(height: 16),
            Text(
              '${correction.status.label} by ${correction.decidedByName}',
              style: textTheme.bodySmall?.copyWith(color: palette.steel),
            ),
            if (correction.decisionReason != null)
              Text(
                'Reason: ${correction.decisionReason}',
                style: textTheme.bodySmall?.copyWith(color: palette.steel),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.palette,
    required this.textTheme,
    this.valueColor,
  });

  final String label;
  final String value;
  final FieldOpsPalette palette;
  final TextTheme textTheme;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: palette.steel),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final CorrectionStatus status;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FieldOpsRadius.full),
      ),
      child: Text(
        status.label,
        style: textTheme.labelSmall?.copyWith(
          color: status.color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({
    required this.correction,
    required this.onAction,
  });

  final TimeCorrection correction;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showDenyDialog(context, ref),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Deny'),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.danger,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _approve(context, ref),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Approve'),
            style: FilledButton.styleFrom(
              backgroundColor: palette.success,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Correction'),
        content: Text(
          'Approve time correction for ${correction.workerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repository = ref.read(timeCorrectionRepositoryProvider);
      await repository.decideCorrection(
        correctionId: correction.id,
        decision: 'approved',
      );

      onAction();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correction approved')),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showDenyDialog(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deny Correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Deny time correction for ${correction.workerName}?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(reasonController.text),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Deny'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      final repository = ref.read(timeCorrectionRepositoryProvider);
      await repository.decideCorrection(
        correctionId: correction.id,
        decision: 'denied',
        reason: result.isEmpty ? null : result,
      );

      onAction();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correction denied')),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.status,
    required this.palette,
    required this.textTheme,
  });

  final CorrectionStatus status;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      CorrectionStatus.pending => 'No pending corrections',
      CorrectionStatus.approved => 'No approved corrections',
      CorrectionStatus.denied => 'No denied corrections',
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: palette.steel.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(message, style: textTheme.titleLarge),
        ],
      ),
    );
  }
}

// Providers
final _pendingCorrectionsProvider =
    FutureProvider<List<TimeCorrection>>((ref) async {
  final repository = ref.watch(timeCorrectionRepositoryProvider);
  return repository.fetchCorrections(status: 'pending');
});

final _approvedCorrectionsProvider =
    FutureProvider<List<TimeCorrection>>((ref) async {
  final repository = ref.watch(timeCorrectionRepositoryProvider);
  return repository.fetchCorrections(status: 'approved');
});

final _deniedCorrectionsProvider =
    FutureProvider<List<TimeCorrection>>((ref) async {
  final repository = ref.watch(timeCorrectionRepositoryProvider);
  return repository.fetchCorrections(status: 'denied');
});

final _correctionsProvider =
    FutureProvider.family<List<TimeCorrection>, String>((ref, status) async {
  final repository = ref.watch(timeCorrectionRepositoryProvider);
  return repository.fetchCorrections(status: status);
});

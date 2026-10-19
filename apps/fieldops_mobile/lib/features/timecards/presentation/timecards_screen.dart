import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_repository.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_signature.dart';
import 'package:fieldops_mobile/features/timecards/presentation/timecards_controller.dart';
import 'package:fieldops_mobile/features/timecards/presentation/widgets/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimecardsScreen extends ConsumerWidget {
  const TimecardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timecardsProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Timecards'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(timecardsProvider.notifier).reload(),
        child: state.when(
          data: (timecards) {
            if (timecards.isEmpty) {
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
              itemCount: timecards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _TimecardCard(period: timecards[index]),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(itemCount: 3),
          ),
          error: (error, _) {
            final message = error is TimecardRepositoryException
                ? error.message
                : 'Could not load timecards.';
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

// ─── Timecard Card ────────────────────────────────────────────

class _TimecardCard extends ConsumerStatefulWidget {
  const _TimecardCard({required this.period});

  final TimecardPeriod period;

  @override
  ConsumerState<_TimecardCard> createState() => _TimecardCardState();
}

class _TimecardCardState extends ConsumerState<_TimecardCard> {
  bool _isSigning = false;
  bool _showSignaturePad = false;

  Future<void> _sign({Uint8List? signatureImage}) async {
    setState(() => _isSigning = true);
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(timecardsProvider.notifier)
          .sign(widget.period.id, signatureImage: signatureImage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timecard signed')),
        );
        setState(() => _showSignaturePad = false);
      }
    } on TimecardRepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final p = widget.period;

    final start = '${p.periodStart.month}/${p.periodStart.day}';
    final end = '${p.periodEnd.month}/${p.periodEnd.day}';

    final statusColor = p.isFullySigned
        ? palette.success
        : p.isWorkerSigned
            ? palette.signal
            : palette.steel;
    final statusLabel = p.isFullySigned
        ? 'Fully Signed'
        : p.isWorkerSigned
            ? 'Awaiting Supervisor'
            : 'Unsigned';

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
                  color: palette.muted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.description_rounded,
                    size: 22, color: palette.steel),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$start \u2013 $end', style: textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Pay period',
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
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                ),
                child: Text(
                  statusLabel,
                  style: textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Hours breakdown
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.muted,
              borderRadius: BorderRadius.circular(FieldOpsRadius.md),
            ),
            child: Row(
              children: [
                _HoursColumn(
                  label: 'Regular',
                  hours: p.totalRegularHours,
                  color: palette.slate,
                  textTheme: textTheme,
                ),
                const SizedBox(width: 20),
                _HoursColumn(
                  label: 'OT',
                  hours: p.totalOTHours,
                  color: palette.signal,
                  textTheme: textTheme,
                ),
                const SizedBox(width: 20),
                _HoursColumn(
                  label: '2x',
                  hours: p.totalDoubleTimeHours,
                  color: palette.danger,
                  textTheme: textTheme,
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${p.totalHours.toStringAsFixed(1)}h',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('Total', style: textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),

          // Signature status
          if (p.isWorkerSigned) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 16, color: palette.success),
                const SizedBox(width: 6),
                Text(
                  'Signed by you on ${_formatDate(p.workerSignature!.signedAt)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.success,
                  ),
                ),
              ],
            ),
          ],

          // Sign button or signature pad
          if (!p.isWorkerSigned) ...[
            const SizedBox(height: 14),
            if (_showSignaturePad) ...[
              SignaturePad(
                onSigned: (bytes) => _sign(signatureImage: bytes),
                onCancel: () => setState(() => _showSignaturePad = false),
              ),
            ] else ...[
              Semantics(
                button: true,
                label: 'Sign timecard for $start to $end',
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSigning
                        ? null
                        : () => setState(() => _showSignaturePad = true),
                    icon: _isSigning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.draw_rounded),
                    label: const Text('Sign Timecard'),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
}

class _HoursColumn extends StatelessWidget {
  const _HoursColumn({
    required this.label,
    required this.hours,
    required this.color,
    required this.textTheme,
  });

  final String label;
  final double hours;
  final Color color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${hours.toStringAsFixed(1)}h',
          style: textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(label, style: textTheme.labelSmall),
      ],
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
          Icons.description_rounded,
          size: 48,
          color: palette.steel.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 12),
        Text('No timecards yet', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Timecards will appear here at the end of each pay period.',
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
        Text('Timecards unavailable', style: textTheme.titleLarge),
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

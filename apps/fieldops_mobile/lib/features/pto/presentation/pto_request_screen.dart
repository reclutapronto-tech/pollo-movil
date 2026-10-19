import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:fieldops_mobile/features/pto/presentation/pto_balance_controller.dart';
import 'package:fieldops_mobile/features/pto/presentation/pto_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PTORequestScreen extends ConsumerStatefulWidget {
  const PTORequestScreen({super.key});

  @override
  ConsumerState<PTORequestScreen> createState() => _PTORequestScreenState();
}

class _PTORequestScreenState extends ConsumerState<PTORequestScreen> {
  String _type = 'vacation';
  DateTime? _startDate;
  DateTime? _endDate;
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_startDate == null || _endDate == null) return;

    await ref.read(ptoControllerProvider.notifier).submit(
          type: _type,
          startDate: _startDate!,
          endDate: _endDate!,
          notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        );

    if (!mounted) return;
    final state = ref.read(ptoControllerProvider);
    if (state.submitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PTO request submitted')),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final controllerState = ref.watch(ptoControllerProvider);
    final ptoList = ref.watch(ptoListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Off Request'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // PTO Balance summary
          _PTOBalanceCard(palette: palette, textTheme: textTheme),
          const SizedBox(height: 20),

          // Type selector
          Text('Type', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'vacation', label: Text('Vacation')),
              ButtonSegment(value: 'sick', label: Text('Sick')),
              ButtonSegment(value: 'personal', label: Text('Personal')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),

          const SizedBox(height: 24),

          // Date pickers
          Row(
            children: [
              Expanded(
                child: _DateTile(
                  label: 'Start Date',
                  date: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTile(
                  label: 'End Date',
                  date: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),

          if (_startDate != null && _endDate != null) ...[
            const SizedBox(height: 12),
            Text(
              '${_endDate!.difference(_startDate!).inDays + 1} day(s)',
              style: textTheme.bodyMedium?.copyWith(color: palette.steel),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 24),

          // Notes
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),

          if (controllerState.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                controllerState.error!,
                style: textTheme.bodySmall?.copyWith(color: palette.danger),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Submit
          FilledButton(
            onPressed: _startDate != null && _endDate != null && !controllerState.isSubmitting
                ? _submit
                : null,
            child: controllerState.isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Submit Request'),
          ),

          const SizedBox(height: 32),

          // My requests
          Text('My Requests', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          ptoList.when(
            data: (requests) {
              if (requests.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No time off requests yet.',
                      style: textTheme.bodyMedium?.copyWith(color: palette.steel),
                    ),
                  ),
                );
              }
              return Column(
                children: requests.map((r) => _PTOCard(request: r)).toList(),
              );
            },
            loading: () => const SkeletonLoader(itemCount: 2),
            error: (e, _) => Text('Failed to load: $e'),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: date != null
          ? '$label: ${date!.month}/${date!.day}/${date!.year}'
          : '$label: not selected, tap to choose',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              date != null
                  ? '${date!.month}/${date!.day}/${date!.year}'
                  : 'Select...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: date != null ? palette.slate : palette.steel,
                  ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _PTOCard extends StatelessWidget {
  const _PTOCard({required this.request});

  final PTORequest request;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final statusColor = switch (request.status) {
      'approved' => palette.success,
      'denied' => palette.danger,
      'cancelled' => palette.steel,
      _ => palette.signal,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.type[0].toUpperCase()}${request.type.substring(1)}',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${request.startDate.month}/${request.startDate.day} – ${request.endDate.month}/${request.endDate.day} (${request.dayCount}d)',
                  style: textTheme.bodySmall?.copyWith(color: palette.steel),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              request.status.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PTOBalanceCard extends ConsumerWidget {
  const _PTOBalanceCard({required this.palette, required this.textTheme});

  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceState = ref.watch(ptoBalanceProvider);

    return balanceState.when(
      data: (balance) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surfaceWhite,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PTO Balance', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _BalanceChip(
                  label: 'Vacation',
                  remaining: balance.vacationRemaining,
                  total: balance.vacationTotal,
                  color: const Color(0xFF2563EB),
                  palette: palette,
                  textTheme: textTheme,
                ),
                const SizedBox(width: 10),
                _BalanceChip(
                  label: 'Sick',
                  remaining: balance.sickRemaining,
                  total: balance.sickTotal,
                  color: const Color(0xFFDC2626),
                  palette: palette,
                  textTheme: textTheme,
                ),
                const SizedBox(width: 10),
                _BalanceChip(
                  label: 'Personal',
                  remaining: balance.personalRemaining,
                  total: balance.personalTotal,
                  color: const Color(0xFF7C3AED),
                  palette: palette,
                  textTheme: textTheme,
                ),
              ],
            ),
          ],
        ),
      ),
      loading: () => Container(
        height: 88,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.muted,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        ),
        child: Center(
          child: Text('Loading balance...', style: textTheme.bodySmall),
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.muted,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: palette.steel),
            const SizedBox(width: 8),
            Text(
              'PTO balance unavailable',
              style: textTheme.bodySmall?.copyWith(color: palette.steel),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({
    required this.label,
    required this.remaining,
    required this.total,
    required this.color,
    required this.palette,
    required this.textTheme,
  });

  final String label;
  final double remaining;
  final double total;
  final Color color;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        ),
        child: Column(
          children: [
            Text(
              remaining.toStringAsFixed(remaining.truncateToDouble() == remaining ? 0 : 1),
              style: textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'of ${total.toStringAsFixed(0)}d',
              style: textTheme.labelSmall?.copyWith(
                color: palette.steel,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

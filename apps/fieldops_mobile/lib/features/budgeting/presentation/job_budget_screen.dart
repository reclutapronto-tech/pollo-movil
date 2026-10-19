import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/auth/domain/user_role.dart';
import 'package:fieldops_mobile/features/budgeting/data/budget_repository_provider.dart';
import 'package:fieldops_mobile/features/budgeting/data/supabase_budget_repository.dart';
import 'package:fieldops_mobile/features/budgeting/domain/budget_repository.dart';
import 'package:fieldops_mobile/features/budgeting/presentation/budget_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen showing budget vs actual for a specific job. When no budget
/// exists for the job yet, supervisors/admins see a "Create budget"
/// button instead of a bare error state.
class JobBudgetScreen extends ConsumerWidget {
  const JobBudgetScreen({
    super.key,
    required this.jobId,
    required this.jobName,
  });

  final String jobId;
  final String jobName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetAsync = ref.watch(_jobBudgetProvider(jobId));
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;
    final role = ref.watch(userRoleProvider);
    final canEdit = role == UserRole.supervisor || role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: Text(jobName),
        leading: const BackButton(),
      ),
      body: budgetAsync.when(
        data: (budget) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BudgetCard(budget: budget),
              const SizedBox(height: 24),
              _LaborBreakdownSection(
                budget: budget,
                palette: palette,
                textTheme: textTheme,
              ),
            ],
          ),
        ),
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonLoader(itemCount: 3),
        ),
        error: (error, _) {
          final message = error.toString();
          final isMissing = message.toLowerCase().contains('no budget');
          return _BudgetErrorState(
            palette: palette,
            textTheme: textTheme,
            message: message,
            missing: isMissing,
            canCreate: canEdit,
            onCreate: () => _openCreateSheet(context, ref),
          );
        },
      ),
      floatingActionButton: canEdit
          ? budgetAsync.maybeWhen(
              // Only surface the FAB when a budget already exists — in the
              // missing-budget error state we render the big "Create budget"
              // CTA in the body instead.
              data: (_) => FloatingActionButton.extended(
                onPressed: () => _openCreateSheet(context, ref),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Replace budget'),
              ),
              orElse: () => null,
            )
          : null,
    );
  }

  Future<void> _openCreateSheet(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateBudgetSheet(jobId: jobId, jobName: jobName),
    );
    if (created == true) {
      ref.invalidate(_jobBudgetProvider(jobId));
    }
  }
}

class _BudgetErrorState extends StatelessWidget {
  const _BudgetErrorState({
    required this.palette,
    required this.textTheme,
    required this.message,
    required this.missing,
    required this.canCreate,
    required this.onCreate,
  });

  final FieldOpsPalette palette;
  final TextTheme textTheme;
  final String message;
  final bool missing;
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              missing ? Icons.savings_outlined : Icons.error_outline,
              size: 48,
              color: missing ? palette.steel : palette.danger,
            ),
            const SizedBox(height: 12),
            Text(
              missing ? 'No budget yet for this job' : 'Failed to load budget',
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              missing
                  ? 'Set a budget so the job-detail view shows labor and '
                      'cost variance in real time.'
                  : message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: palette.steel),
            ),
            if (missing && canCreate) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateBudgetSheet extends ConsumerStatefulWidget {
  const _CreateBudgetSheet({
    required this.jobId,
    required this.jobName,
  });

  final String jobId;
  final String jobName;

  @override
  ConsumerState<_CreateBudgetSheet> createState() => _CreateBudgetSheetState();
}

class _CreateBudgetSheetState extends ConsumerState<_CreateBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _hoursCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _thresholdCtrl = TextEditingController(text: '80');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _costCtrl.dispose();
    _rateCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final hours = double.parse(_hoursCtrl.text.trim());
    final cost = double.parse(_costCtrl.text.trim());
    final rateText = _rateCtrl.text.trim();
    final rate = rateText.isEmpty ? null : double.tryParse(rateText);
    final thresholdText = _thresholdCtrl.text.trim();
    final threshold =
        thresholdText.isEmpty ? null : double.tryParse(thresholdText);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(budgetRepositoryProvider).createJobBudget(
            jobId: widget.jobId,
            budgetedHours: hours,
            budgetedCost: cost,
            hourlyRate: rate,
            warningThresholdPercent: threshold,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BudgetException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } on Object catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + insets),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set budget for ${widget.jobName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hoursCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Budgeted hours',
                hintText: 'e.g. 120',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed = double.tryParse(v?.trim() ?? '');
                if (parsed == null || parsed <= 0) return 'Must be > 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _costCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Budgeted cost (USD)',
                hintText: 'e.g. 8400',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed = double.tryParse(v?.trim() ?? '');
                if (parsed == null || parsed <= 0) return 'Must be > 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Hourly rate',
                      hintText: 'Derived if blank',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _thresholdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Warn at %',
                      hintText: '80',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final parsed = double.tryParse(v.trim());
                      if (parsed == null || parsed <= 0 || parsed > 100) {
                        return '1–100';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: palette.danger, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LaborBreakdownSection extends StatelessWidget {
  const _LaborBreakdownSection({
    required this.budget,
    required this.palette,
    required this.textTheme,
  });

  final JobBudgetSummary budget;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
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
          Text('Labor Breakdown', style: textTheme.titleMedium),
          const SizedBox(height: 16),
          _InfoRow(
            label: 'Hourly Rate',
            value: '\$${budget.hourlyRate.toStringAsFixed(2)}',
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Budgeted Hours',
            value: '${budget.budgetedHours.toStringAsFixed(1)}h',
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Actual Hours',
            value: '${budget.actualHours.toStringAsFixed(1)}h',
            valueColor: budget.isOverHours ? palette.danger : null,
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Efficiency',
            value:
                '${budget.actualHours > 0 ? ((budget.budgetedHours / budget.actualHours) * 100).clamp(0, 999).toStringAsFixed(0) : 0}%',
            palette: palette,
            textTheme: textTheme,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(color: palette.steel),
        ),
        Text(
          value,
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// Provider for job budget
final _jobBudgetProvider =
    FutureProvider.family<JobBudgetSummary, String>((ref, jobId) async {
  final repository = ref.watch(budgetRepositoryProvider);
  return repository.fetchJobBudget(jobId);
});

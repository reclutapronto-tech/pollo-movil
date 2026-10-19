import 'dart:async';
import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_capture_screen.dart';
import 'package:fieldops_mobile/features/expenses/data/expense_repository_provider.dart';
import 'package:fieldops_mobile/features/expenses/domain/expense_category_suggester.dart';
import 'package:fieldops_mobile/features/expenses/domain/expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpenseCaptureScreen extends ConsumerStatefulWidget {
  const ExpenseCaptureScreen({
    super.key,
    required this.jobId,
    required this.jobName,
    this.onCaptureReceiptPhoto,
  });

  final String jobId;
  final String jobName;
  final Future<PhotoCaptureResult?> Function(BuildContext context)?
  onCaptureReceiptPhoto;

  @override
  ConsumerState<ExpenseCaptureScreen> createState() =>
      _ExpenseCaptureScreenState();
}

class _ExpenseCaptureScreenState extends ConsumerState<ExpenseCaptureScreen> {
  final _amountController = TextEditingController();
  final _vendorController = TextEditingController();
  final _notesController = TextEditingController();
  String _category = 'materials';
  String? _suggestedCategory;
  bool _didOverrideCategory = false;
  bool _isSubmitting = false;
  String? _error;
  bool _photoTaken = false;
  String? _mediaAssetId;

  static const _categories = [
    ('materials', 'Materials', Icons.inventory_2_rounded),
    ('fuel', 'Fuel', Icons.local_gas_station_rounded),
    ('tools', 'Tools', Icons.construction_rounded),
    ('meals', 'Meals', Icons.restaurant_rounded),
    ('other', 'Other', Icons.receipt_long_rounded),
  ];

  static final Map<String, String> _categoryLabels = {
    for (final entry in _categories) entry.$1: entry.$2,
  };

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _vendorController.addListener(_onCategoryInputChanged);
    _notesController.addListener(_onCategoryInputChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _vendorController.removeListener(_onCategoryInputChanged);
    _notesController.removeListener(_onCategoryInputChanged);
    _amountController.dispose();
    _vendorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onCategoryInputChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _updateSuggestedCategory);
  }

  void _updateSuggestedCategory() {
    final suggestion = suggestExpenseCategory(
      vendor: _vendorController.text,
      notes: _notesController.text,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _suggestedCategory = suggestion;
      if (!_didOverrideCategory && suggestion != null) {
        _category = suggestion;
      }
    });
  }

  Future<void> _takeReceiptPhoto() async {
    final result =
        await (widget.onCaptureReceiptPhoto?.call(context) ??
            Navigator.of(context).push<PhotoCaptureResult?>(
              MaterialPageRoute<PhotoCaptureResult?>(
                builder: (_) => CameraCaptureScreen(
                  jobId: widget.jobId,
                  jobName: 'Receipt: ${widget.jobName}',
                ),
              ),
            ));
    if (result != null && result.isUploaded && mounted) {
      setState(() {
        _photoTaken = true;
        _mediaAssetId = result.mediaAssetId;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (!_photoTaken || _mediaAssetId == null) {
      setState(() => _error = 'Take a receipt photo before submitting.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref
          .read(expenseRepositoryProvider)
          .submitExpense(
            jobId: widget.jobId,
            category: _category,
            amount: amount,
            vendor: _vendorController.text.isNotEmpty
                ? _vendorController.text
                : null,
            notes: _notesController.text.isNotEmpty
                ? _notesController.text
                : null,
            mediaAssetId: _mediaAssetId,
          );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Expense submitted')));
        Navigator.of(context).pop(true);
      }
    } on ExpenseRepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Expense'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(FieldOpsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job context
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FieldOpsSpacing.base),
              decoration: BoxDecoration(
                color: palette.muted,
                borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: palette.signal),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.jobName, style: textTheme.titleLarge),
                      Text('Expense for this job', style: textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: FieldOpsSpacing.xl),

            // Receipt photo button
            Text('Receipt photo', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _photoTaken
                      ? palette.success
                      : palette.signal,
                  side: BorderSide(
                    color: _photoTaken
                        ? palette.success.withValues(alpha: 0.4)
                        : palette.signal.withValues(alpha: 0.4),
                  ),
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                  ),
                ),
                onPressed: _takeReceiptPhoto,
                icon: Icon(
                  _photoTaken
                      ? Icons.check_circle_rounded
                      : Icons.camera_alt_rounded,
                ),
                label: Text(
                  _photoTaken ? 'Receipt photo taken' : 'Take receipt photo',
                ),
              ),
            ),
            const SizedBox(height: FieldOpsSpacing.xl),

            // Category selector
            Text('Category', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final isSelected = _category == cat.$1;
                return Semantics(
                  button: true,
                  label: cat.$2,
                  selected: isSelected,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _category = cat.$1;
                      _didOverrideCategory = true;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? palette.signal.withValues(alpha: 0.12)
                            : palette.muted,
                        borderRadius: BorderRadius.circular(
                          FieldOpsRadius.full,
                        ),
                        border: Border.all(
                          color: isSelected ? palette.signal : palette.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat.$3,
                            size: 18,
                            color: isSelected ? palette.signal : palette.steel,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat.$2,
                            style: textTheme.labelMedium?.copyWith(
                              color: isSelected
                                  ? palette.signal
                                  : palette.steel,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_suggestedCategory != null &&
                _suggestedCategory == _category) ...[
              const SizedBox(height: 10),
              Text(
                'Suggested from vendor/notes: ${_labelForCategory(_suggestedCategory!)}',
                style: textTheme.bodySmall?.copyWith(color: palette.steel),
              ),
            ],
            const SizedBox(height: FieldOpsSpacing.xl),

            // Amount
            Text('Amount', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
                prefixIcon: Icon(Icons.attach_money_rounded),
              ),
            ),
            const SizedBox(height: FieldOpsSpacing.base),

            // Vendor
            Text('Vendor (optional)', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vendorController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'e.g. Home Depot',
                prefixIcon: Icon(Icons.store_rounded),
              ),
            ),
            const SizedBox(height: FieldOpsSpacing.base),

            // Notes
            Text('Notes (optional)', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'What was purchased and why',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Icon(Icons.notes_rounded),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: FieldOpsSpacing.base),
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
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(color: palette.danger),
                ),
              ),
            ],

            const SizedBox(height: FieldOpsSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Expense'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelForCategory(String category) {
    return _categoryLabels[category] ?? 'Other';
  }
}

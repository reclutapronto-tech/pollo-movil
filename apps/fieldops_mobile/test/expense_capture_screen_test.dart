import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/expenses/data/expense_repository_provider.dart';
import 'package:fieldops_mobile/features/expenses/domain/expense_repository.dart';
import 'package:fieldops_mobile/features/expenses/presentation/expense_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits captured receipt media asset with expense payload', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [expenseRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildFieldOpsTheme(),
          home: ExpenseCaptureScreen(
            jobId: 'job-1',
            jobName: 'Grid Restoration',
            onCaptureReceiptPhoto: (_) async =>
                const PhotoCaptureResult.uploaded(
                  mediaAssetId: 'media-asset-123',
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '42.50');
    await tester.tap(find.text('Take receipt photo'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt photo taken'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.send_rounded));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(repository.submitCount, 1);
    expect(repository.lastMediaAssetId, 'media-asset-123');
  });

  testWidgets('requires a receipt photo before submitting an expense', (
    tester,
  ) async {
    final repository = _FakeExpenseRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [expenseRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildFieldOpsTheme(),
          home: const ExpenseCaptureScreen(
            jobId: 'job-1',
            jobName: 'Grid Restoration',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '42.50');
    await tester.ensureVisible(find.byIcon(Icons.send_rounded));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(repository.submitCount, 0);
    expect(find.text('Take a receipt photo before submitting.'), findsOneWidget);
  });
}

class _FakeExpenseRepository implements ExpenseRepository {
  String? lastMediaAssetId;
  int submitCount = 0;

  @override
  Future<List<ExpenseRecord>> fetchMyExpenses() async => [];

  @override
  Future<String> submitExpense({
    required String jobId,
    required String category,
    required double amount,
    String? vendor,
    String? notes,
    String? mediaAssetId,
  }) async {
    submitCount += 1;
    lastMediaAssetId = mediaAssetId;
    return 'expense-1';
  }
}

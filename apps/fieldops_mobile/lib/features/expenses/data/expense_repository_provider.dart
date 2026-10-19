import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/expenses/data/supabase_expense_repository.dart';
import 'package:fieldops_mobile/features/expenses/domain/expense_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredExpenseRepository();
  }
  return SupabaseExpenseRepository(Supabase.instance.client);
});

class _UnconfiguredExpenseRepository implements ExpenseRepository {
  const _UnconfiguredExpenseRepository();

  @override
  Future<List<ExpenseRecord>> fetchMyExpenses() {
    throw const ExpenseRepositoryException.unknown('Missing Supabase configuration.');
  }

  @override
  Future<String> submitExpense({
    required String jobId,
    required String category,
    required double amount,
    String? vendor,
    String? notes,
    String? mediaAssetId,
  }) {
    throw const ExpenseRepositoryException.unknown('Missing Supabase configuration.');
  }
}

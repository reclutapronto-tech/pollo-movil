import 'package:fieldops_mobile/features/budgeting/domain/budget_repository.dart';
import 'package:fieldops_mobile/features/budgeting/data/supabase_budget_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for the budget repository.
final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  final client = Supabase.instance.client;
  return SupabaseBudgetRepository(client);
});

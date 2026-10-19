import 'package:fieldops_mobile/features/expenses/data/expense_repository_provider.dart';
import 'package:fieldops_mobile/features/expenses/domain/expense_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final expenseHistoryProvider =
    AsyncNotifierProvider<ExpenseHistoryController, List<ExpenseRecord>>(
      ExpenseHistoryController.new,
    );

class ExpenseHistoryController extends AsyncNotifier<List<ExpenseRecord>> {
  @override
  Future<List<ExpenseRecord>> build() {
    return ref.watch(expenseRepositoryProvider).fetchMyExpenses();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(expenseRepositoryProvider).fetchMyExpenses(),
    );
  }
}

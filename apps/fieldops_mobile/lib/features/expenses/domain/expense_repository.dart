abstract class ExpenseRepository {
  Future<String> submitExpense({
    required String jobId,
    required String category,
    required double amount,
    String? vendor,
    String? notes,
    String? mediaAssetId,
  });

  Future<List<ExpenseRecord>> fetchMyExpenses();
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.category,
    required this.amount,
    required this.createdAt,
    this.vendor,
    this.notes,
    this.status = 'submitted',
  });

  final String id;
  final String jobId;
  final String jobName;
  final String category;
  final double amount;
  final DateTime createdAt;
  final String? vendor;
  final String? notes;
  final String status;
}

enum ExpenseCategory { materials, fuel, tools, meals, other }

enum ExpenseRepositoryErrorType { offline, unknown }

class ExpenseRepositoryException implements Exception {
  const ExpenseRepositoryException._({
    required this.type,
    required this.message,
  });

  const ExpenseRepositoryException.offline()
      : this._(
          type: ExpenseRepositoryErrorType.offline,
          message: 'No connection available.',
        );

  const ExpenseRepositoryException.unknown([
    String message = 'Expense could not be submitted.',
  ]) : this._(type: ExpenseRepositoryErrorType.unknown, message: message);

  final ExpenseRepositoryErrorType type;
  final String message;

  @override
  String toString() => 'ExpenseRepositoryException($type): $message';
}

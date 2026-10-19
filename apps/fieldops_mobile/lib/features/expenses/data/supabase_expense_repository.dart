import 'dart:io';

import 'package:fieldops_mobile/features/expenses/domain/expense_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseExpenseRepository implements ExpenseRepository {
  const SupabaseExpenseRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<List<ExpenseRecord>> fetchMyExpenses() async {
    try {
      final response = await _client.functions.invoke(
        'expenses',
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {'action': 'list'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ExpenseRepositoryException.unknown(
          'Expense list response malformed.',
        );
      }

      final items = (payload['expenses'] as List<dynamic>?) ?? [];
      return items.map((item) {
        final map = item as Map<String, dynamic>;
        return ExpenseRecord(
          id: map['id'] as String? ?? '',
          jobId: map['job_id'] as String? ?? '',
          jobName: map['job_name'] as String? ?? 'Unknown job',
          category: map['category'] as String? ?? 'other',
          amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
          createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
              DateTime.now(),
          vendor: map['vendor'] as String?,
          notes: map['notes'] as String?,
          status: map['status'] as String? ?? 'submitted',
        );
      }).toList();
    } on SocketException {
      throw const ExpenseRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const ExpenseRepositoryException.offline();
      throw ExpenseRepositoryException.unknown(
        'Could not load expenses (${error.status}).',
      );
    }
  }

  @override
  Future<String> submitExpense({
    required String jobId,
    required String category,
    required double amount,
    String? vendor,
    String? notes,
    String? mediaAssetId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'expenses',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'submit',
          'job_id': jobId,
          'category': category,
          'amount': amount,
          if (vendor != null) 'vendor': vendor,
          if (notes != null) 'notes': notes,
          if (mediaAssetId != null) 'media_asset_id': mediaAssetId,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const ExpenseRepositoryException.unknown('Expense response malformed.');
      }

      return payload['expense_id'] as String? ?? '';
    } on SocketException {
      throw const ExpenseRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const ExpenseRepositoryException.offline();
      throw ExpenseRepositoryException.unknown('Expense failed (${error.status}).');
    }
  }
}

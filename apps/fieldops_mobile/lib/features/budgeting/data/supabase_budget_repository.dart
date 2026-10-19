import 'package:fieldops_mobile/features/budgeting/domain/budget_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseBudgetRepository implements BudgetRepository {
  const SupabaseBudgetRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<JobBudgetSummary> fetchJobBudget(String jobId) async {
    try {
      final response = await _client.functions.invoke(
        'budget',
        method: HttpMethod.get,
        headers: {'X-Client-Version': 'fieldops-mobile'},
        queryParameters: {
          'job_id': jobId,
          'summary': 'true',
        },
      );

      final data = response.data as Map<String, dynamic>;
      if (data['budget'] == null) {
        throw const BudgetException('No budget found for this job');
      }

      return JobBudgetSummary.fromJson(data['budget'] as Map<String, dynamic>);
    } on FunctionException catch (error) {
      if (error.status == 0) throw const BudgetException.offline();
      throw BudgetException('Failed to load budget: ${error.details}');
    } catch (e) {
      throw BudgetException('Failed to load budget: $e');
    }
  }

  @override
  Future<List<JobBudgetSummary>> fetchCompanyBudgets() async {
    try {
      final response = await _client.functions.invoke(
        'budget',
        method: HttpMethod.get,
        headers: {'X-Client-Version': 'fieldops-mobile'},
      );

      final data = response.data as Map<String, dynamic>;
      final budgets = data['budgets'] as List<dynamic>? ?? [];

      return budgets
          .map((b) => JobBudgetSummary.fromJson(b as Map<String, dynamic>))
          .toList();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const BudgetException.offline();
      throw BudgetException('Failed to load budgets: ${error.details}');
    } catch (e) {
      throw BudgetException('Failed to load budgets: $e');
    }
  }

  @override
  Future<void> createJobBudget({
    required String jobId,
    required double budgetedHours,
    required double budgetedCost,
    double? hourlyRate,
    double? warningThresholdPercent,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'budget',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'create',
          'job_id': jobId,
          'budgeted_hours': budgetedHours,
          'budgeted_cost': budgetedCost,
          'hourly_rate': hourlyRate,
          'warning_threshold_percent': warningThresholdPercent ?? 80.0,
        },
      );

      if (response.status != 201 && response.status != 200) {
        throw const BudgetException('Failed to create budget');
      }
    } on FunctionException catch (error) {
      if (error.status == 0) throw const BudgetException.offline();
      throw BudgetException('Failed to create budget: ${error.details}');
    } catch (e) {
      throw BudgetException('Failed to create budget: $e');
    }
  }
}

class BudgetException implements Exception {
  const BudgetException(this.message);
  const BudgetException.offline() : message = 'Connection unavailable';

  final String message;

  @override
  String toString() => message;
}

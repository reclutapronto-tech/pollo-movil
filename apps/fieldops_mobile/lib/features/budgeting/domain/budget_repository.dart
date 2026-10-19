/// Repository for managing job budgets and tracking budget vs actual.
abstract class BudgetRepository {
  /// Fetch budget summary for a specific job.
  Future<JobBudgetSummary> fetchJobBudget(String jobId);

  /// Fetch all job budgets for the company.
  Future<List<JobBudgetSummary>> fetchCompanyBudgets();

  /// Create a new budget for a job (supervisor/admin only).
  Future<void> createJobBudget({
    required String jobId,
    required double budgetedHours,
    required double budgetedCost,
    double? hourlyRate,
    double? warningThresholdPercent,
  });
}

/// Extended job budget with actual values from database.
class JobBudgetSummary {
  const JobBudgetSummary({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.jobCode,
    required this.jobStatus,
    required this.budgetedHours,
    required this.budgetedCost,
    required this.hourlyRate,
    required this.warningThresholdPercent,
    required this.actualHours,
    required this.actualCost,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String jobId;
  final String jobName;
  final String jobCode;
  final String jobStatus;
  final double budgetedHours;
  final double budgetedCost;
  final double hourlyRate;
  final double warningThresholdPercent;
  final double actualHours;
  final double actualCost;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Hours variance (positive = over budget)
  double get hoursVariance => actualHours - budgetedHours;

  /// Cost variance (positive = over budget)
  double get costVariance => actualCost - budgetedCost;

  /// Whether job is over budget
  bool get isOverBudget => actualCost > budgetedCost;

  /// Whether hours are over budget
  bool get isOverHours => actualHours > budgetedHours;

  /// Hours completion percentage
  double get hoursCompletionPercent =>
      budgetedHours > 0 ? (actualHours / budgetedHours * 100).clamp(0, 999) : 0;

  /// Cost completion percentage
  double get costCompletionPercent =>
      budgetedCost > 0 ? (actualCost / budgetedCost * 100).clamp(0, 999) : 0;

  /// Whether budget is approaching threshold (e.g., 80%)
  bool get isApproachingLimit =>
      hoursCompletionPercent >= warningThresholdPercent ||
      costCompletionPercent >= warningThresholdPercent;

  factory JobBudgetSummary.fromJson(Map<String, dynamic> json) {
    return JobBudgetSummary(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      jobName: json['job_name'] as String? ?? 'Unknown',
      jobCode: json['job_code'] as String? ?? '',
      jobStatus: json['job_status'] as String? ?? 'active',
      budgetedHours: (json['budgeted_hours'] as num?)?.toDouble() ?? 0,
      budgetedCost: (json['budgeted_cost'] as num?)?.toDouble() ?? 0,
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ?? 0,
      warningThresholdPercent:
          (json['warning_threshold_percent'] as num?)?.toDouble() ?? 80.0,
      actualHours: (json['actual_hours'] as num?)?.toDouble() ?? 0,
      actualCost: (json['actual_cost'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

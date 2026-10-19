/// Job budgeting model — budget vs actual labor costs.
class JobBudget {
  const JobBudget({
    required this.jobId,
    required this.jobName,
    this.budgetedHours = 0,
    this.actualHours = 0,
    this.budgetedCost = 0,
    this.actualCost = 0,
    this.costPerHour = 0,
  });

  final String jobId;
  final String jobName;
  final double budgetedHours;
  final double actualHours;
  final double budgetedCost;
  final double actualCost;
  final double costPerHour;

  double get hoursVariance => actualHours - budgetedHours;
  double get costVariance => actualCost - budgetedCost;
  bool get isOverBudget => actualCost > budgetedCost;
  double get completionPercent =>
      budgetedHours > 0 ? (actualHours / budgetedHours * 100).clamp(0, 999) : 0;
}

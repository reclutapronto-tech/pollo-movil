class WorkerHoursSnapshot {
  const WorkerHoursSnapshot({
    required this.hoursToday,
    required this.hoursThisWeek,
    required this.hoursThisMonth,
  });

  final double hoursToday;
  final double hoursThisWeek;
  final double hoursThisMonth;

  factory WorkerHoursSnapshot.fromJson(Map<String, dynamic> json) {
    return WorkerHoursSnapshot(
      hoursToday: (json['hours_today'] as num?)?.toDouble() ?? 0,
      hoursThisWeek: (json['hours_this_week'] as num?)?.toDouble() ?? 0,
      hoursThisMonth: (json['hours_this_month'] as num?)?.toDouble() ?? 0,
    );
  }
}

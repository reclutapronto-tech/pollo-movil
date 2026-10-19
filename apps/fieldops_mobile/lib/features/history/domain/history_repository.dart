/// A single work history entry derived from clock events.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.jobName,
    required this.date,
    required this.clockInAt,
    this.clockOutAt,
    this.regularHours = 0,
    this.otHours = 0,
    this.photosCount = 0,
    this.tasksCompleted = 0,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id'] as String? ?? '',
      jobName: json['job_name'] as String? ?? 'Unknown job',
      date: DateTime.tryParse(json['shift_date'] as String? ?? '') ??
          DateTime.now(),
      clockInAt: DateTime.tryParse(json['clock_in_at'] as String? ?? '') ??
          DateTime.now(),
      clockOutAt: json['clock_out_at'] != null
          ? DateTime.tryParse(json['clock_out_at'] as String)
          : null,
      regularHours: (json['regular_hours'] as num?)?.toDouble() ?? 0,
      otHours: (json['ot_hours'] as num?)?.toDouble() ?? 0,
      photosCount: (json['photos_count'] as num?)?.toInt() ?? 0,
      tasksCompleted: (json['tasks_completed'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String jobName;
  final DateTime date;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final double regularHours;
  final double otHours;
  final int photosCount;
  final int tasksCompleted;

  double get totalHours => regularHours + otHours;

  bool get isActive => clockOutAt == null;
}

/// Summary stats for a time range.
class HistorySummary {
  const HistorySummary({
    this.totalHours = 0,
    this.regularHours = 0,
    this.otHours = 0,
    this.totalJobs = 0,
    this.totalPhotos = 0,
    this.totalTasks = 0,
  });

  final double totalHours;
  final double regularHours;
  final double otHours;
  final int totalJobs;
  final int totalPhotos;
  final int totalTasks;
}

abstract class HistoryRepository {
  /// Fetches recent history entries, newest first.
  Future<List<HistoryEntry>> fetchHistory({int limit = 50});

  /// Fetches summary stats for the given time range.
  Future<HistorySummary> fetchSummary({
    required DateTime from,
    required DateTime to,
  });
}

class HistoryRepositoryException implements Exception {
  const HistoryRepositoryException(this.message);
  const HistoryRepositoryException.unknown()
      : message = 'Could not load work history.';

  final String message;

  @override
  String toString() => message;
}

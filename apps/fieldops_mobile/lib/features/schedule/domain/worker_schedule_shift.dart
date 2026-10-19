enum WorkerScheduleStatus { draft, published }

class WorkerScheduleShift {
  const WorkerScheduleShift({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.publishedAt,
    this.notes,
  });

  factory WorkerScheduleShift.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now().toUtc();
    final statusValue = json['status'] as String? ?? 'published';

    return WorkerScheduleShift(
      id: json['id'] as String? ?? '',
      jobId: json['job_id'] as String? ?? '',
      jobName: json['job_name'] as String? ?? 'Unnamed job',
      shiftDate: DateTime.utc(date.year, date.month, date.day),
      startTime: json['start_time'] as String? ?? '--:--',
      endTime: json['end_time'] as String? ?? '--:--',
      status: statusValue == 'draft'
          ? WorkerScheduleStatus.draft
          : WorkerScheduleStatus.published,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String jobId;
  final String jobName;
  final DateTime shiftDate;
  final String startTime;
  final String endTime;
  final WorkerScheduleStatus status;
  final DateTime? publishedAt;
  final String? notes;

  bool get isRecentlyUpdated {
    final publishedAt = this.publishedAt;
    if (publishedAt == null) return false;
    return DateTime.now().toUtc().difference(publishedAt.toUtc()).inHours <= 24;
  }
}

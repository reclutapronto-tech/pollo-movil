class JobSummary {
  const JobSummary({
    required this.jobId,
    required this.jobName,
    required this.geofenceRadiusM,
    required this.taskCount,
  });

  factory JobSummary.fromJson(Map<String, dynamic> json) {
    final geofence = json['geofence'] as Map<String, dynamic>? ?? const {};
    final tasks = json['tasks'] as List<dynamic>? ?? const [];

    return JobSummary(
      jobId: json['job_id'] as String? ?? '',
      jobName: json['job_name'] as String? ?? 'Unnamed job',
      geofenceRadiusM: (geofence['radius_m'] as num?)?.toInt() ?? 0,
      taskCount: tasks.length,
    );
  }

  final String jobId;
  final String jobName;
  final int geofenceRadiusM;
  final int taskCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobSummary && jobId == other.jobId;

  @override
  int get hashCode => jobId.hashCode;
}

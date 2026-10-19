/// A single shift in the foreman's crew schedule view.
///
/// Extends the base shift data with [workerName] for display and
/// [sortOrder] for drag-to-reorder persistence.
class CrewScheduleShift {
  const CrewScheduleShift({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.workerId,
    required this.workerName,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.sortOrder,
  });

  factory CrewScheduleShift.fromJson(Map<String, dynamic> json) {
    final date =
        DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now().toUtc();

    return CrewScheduleShift(
      id: json['id'] as String? ?? '',
      jobId: json['job_id'] as String? ?? '',
      jobName: json['job_name'] as String? ?? 'Unnamed job',
      workerId: json['worker_id'] as String? ?? '',
      workerName: json['worker_name'] as String? ?? 'Unknown',
      shiftDate: DateTime.utc(date.year, date.month, date.day),
      startTime: json['start_time'] as String? ?? '--:--',
      endTime: json['end_time'] as String? ?? '--:--',
      status: json['status'] as String? ?? 'published',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  final String id;
  final String jobId;
  final String jobName;
  final String workerId;
  final String workerName;
  final DateTime shiftDate;
  final String startTime;
  final String endTime;

  /// One of: draft, published, pending_approval.
  final String status;

  /// Local ordering set by the foreman via drag-to-reorder.
  final int sortOrder;

  CrewScheduleShift copyWith({int? sortOrder}) {
    return CrewScheduleShift(
      id: id,
      jobId: jobId,
      jobName: jobName,
      workerId: workerId,
      workerName: workerName,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      status: status,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toReorderPayload() => {
        'shift_id': id,
        'sort_order': sortOrder,
      };
}

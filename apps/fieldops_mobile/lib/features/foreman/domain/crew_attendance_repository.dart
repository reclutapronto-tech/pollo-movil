/// Crew member clock status for the foreman attendance view.
class CrewMemberStatus {
  const CrewMemberStatus({
    required this.workerId,
    required this.workerName,
    required this.status,
    this.jobName,
    this.clockedInAt,
    this.avatarUrl,
  });

  final String workerId;
  final String workerName;
  final CrewClockStatus status;
  final String? jobName;
  final DateTime? clockedInAt;
  final String? avatarUrl;

  factory CrewMemberStatus.fromJson(Map<String, dynamic> json) {
    return CrewMemberStatus(
      workerId: json['worker_id'] as String,
      workerName: json['worker_name'] as String? ?? 'Unknown',
      status: CrewClockStatus.fromString(json['status'] as String? ?? 'absent'),
      jobName: json['job_name'] as String?,
      clockedInAt: json['clocked_in_at'] != null
          ? DateTime.tryParse(json['clocked_in_at'] as String)
          : null,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

enum CrewClockStatus {
  clockedIn,
  onBreak,
  late_,
  absent;

  static CrewClockStatus fromString(String value) {
    return switch (value) {
      'clocked_in' => CrewClockStatus.clockedIn,
      'on_break' => CrewClockStatus.onBreak,
      'late' => CrewClockStatus.late_,
      _ => CrewClockStatus.absent,
    };
  }

  String get label => switch (this) {
        CrewClockStatus.clockedIn => 'Clocked In',
        CrewClockStatus.onBreak => 'On Break',
        CrewClockStatus.late_ => 'Late',
        CrewClockStatus.absent => 'Absent',
      };
}

/// Fetches crew attendance for the foreman's assigned workers.
abstract class CrewAttendanceRepository {
  Future<List<CrewMemberStatus>> fetchCrewAttendance();
}

class CrewAttendanceException implements Exception {
  const CrewAttendanceException(this.message);
  final String message;

  @override
  String toString() => 'CrewAttendanceException: $message';
}

/// Manual time entry for corrections/overrides.
/// Creates a clock_event with explicit audit trail showing
/// who entered it, when, and why.
class ManualTimeEntry {
  const ManualTimeEntry({
    required this.workerId,
    required this.jobId,
    required this.clockIn,
    required this.clockOut,
    required this.reason,
    required this.enteredBy,
  });

  final String workerId;
  final String jobId;
  final DateTime clockIn;
  final DateTime clockOut;
  final String reason;
  final String enteredBy; // supervisor/admin who entered it

  Duration get duration => clockOut.difference(clockIn);
  double get hours => duration.inMinutes / 60.0;
}

// Time card signature model for digital sign-off.
// Worker signs their timesheet at end of pay period.
// Supervisor counter-signs. Both stored as immutable events.

/// Digital signature on a timecard period.
class TimecardSignature {
  const TimecardSignature({
    required this.id,
    required this.timecardId,
    required this.signerId,
    required this.signerName,
    required this.signerRole,
    required this.signedAt,
    this.signatureImagePath,
  });

  final String id;
  final String timecardId;
  final String signerId;
  final String signerName;
  final String signerRole;
  final DateTime signedAt;
  final String? signatureImagePath;
}

class TimecardPeriod {
  const TimecardPeriod({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.periodStart,
    required this.periodEnd,
    required this.totalRegularHours,
    required this.totalOTHours,
    required this.totalDoubleTimeHours,
    this.workerSignature,
    this.supervisorSignature,
  });

  final String id;
  final String workerId;
  final String workerName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double totalRegularHours;
  final double totalOTHours;
  final double totalDoubleTimeHours;
  final TimecardSignature? workerSignature;
  final TimecardSignature? supervisorSignature;

  bool get isWorkerSigned => workerSignature != null;
  bool get isSupervisorSigned => supervisorSignature != null;
  bool get isFullySigned => isWorkerSigned && isSupervisorSigned;
  double get totalHours => totalRegularHours + totalOTHours + totalDoubleTimeHours;
}

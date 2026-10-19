import 'package:flutter/material.dart';

/// Model representing a time correction request.
class TimeCorrection {
  const TimeCorrection({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.jobId,
    required this.jobName,
    this.originalEventId,
    this.originalEventSubtype,
    this.originalOccurredAt,
    required this.correctedEventSubtype,
    required this.correctedOccurredAt,
    required this.reason,
    this.evidenceNotes,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.status,
    this.decidedBy,
    this.decidedByName,
    this.decidedAt,
    this.decisionReason,
    this.resultingEventId,
  });

  final String id;
  final String workerId;
  final String workerName;
  final String jobId;
  final String jobName;
  final String? originalEventId;
  final String? originalEventSubtype;
  final DateTime? originalOccurredAt;
  final String correctedEventSubtype;
  final DateTime correctedOccurredAt;
  final String reason;
  final String? evidenceNotes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final CorrectionStatus status;
  final String? decidedBy;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionReason;
  final String? resultingEventId;

  bool get isPending => status == CorrectionStatus.pending;
  bool get isApproved => status == CorrectionStatus.approved;
  bool get isDenied => status == CorrectionStatus.denied;

  factory TimeCorrection.fromJson(Map<String, dynamic> json) {
    return TimeCorrection(
      id: json['id'] as String,
      workerId: json['worker_id'] as String,
      workerName: json['worker_name'] as String? ?? 'Unknown',
      jobId: json['job_id'] as String,
      jobName: json['job_name'] as String? ?? 'Unknown',
      originalEventId: json['original_event_id'] as String?,
      originalEventSubtype: json['original_event_subtype'] as String?,
      originalOccurredAt: json['original_occurred_at'] != null
          ? DateTime.tryParse(json['original_occurred_at'] as String)
          : null,
      correctedEventSubtype: json['corrected_event_subtype'] as String,
      correctedOccurredAt: DateTime.parse(json['corrected_occurred_at'] as String),
      reason: json['reason'] as String,
      evidenceNotes: json['evidence_notes'] as String?,
      createdBy: json['created_by'] as String,
      createdByName: json['created_by_name'] as String? ?? 'Unknown',
      createdAt: DateTime.parse(json['created_at'] as String),
      status: CorrectionStatus.fromString(json['status'] as String),
      decidedBy: json['decided_by'] as String?,
      decidedByName: json['decided_by_name'] as String?,
      decidedAt: json['decided_at'] != null
          ? DateTime.tryParse(json['decided_at'] as String)
          : null,
      decisionReason: json['decision_reason'] as String?,
      resultingEventId: json['resulting_event_id'] as String?,
    );
  }
}

enum CorrectionStatus {
  pending,
  approved,
  denied;

  static CorrectionStatus fromString(String value) {
    return switch (value) {
      'approved' => CorrectionStatus.approved,
      'denied' => CorrectionStatus.denied,
      _ => CorrectionStatus.pending,
    };
  }

  String get label => switch (this) {
        CorrectionStatus.pending => 'Pending',
        CorrectionStatus.approved => 'Approved',
        CorrectionStatus.denied => 'Denied',
      };

  Color get color {
    return switch (this) {
      CorrectionStatus.pending => const Color(0xFFF59E0B),
      CorrectionStatus.approved => const Color(0xFF10B981),
      CorrectionStatus.denied => const Color(0xFFEF4444),
    };
  }
}

/// Repository for managing time corrections.
abstract class TimeCorrectionRepository {
  /// Fetch time corrections for the company.
  Future<List<TimeCorrection>> fetchCorrections({
    String? workerId,
    String? jobId,
    String status = 'pending',
  });

  /// Create a new time correction request.
  Future<String> createCorrection({
    required String workerId,
    required String jobId,
    String? originalEventId,
    String? originalEventSubtype,
    DateTime? originalOccurredAt,
    required String correctedEventSubtype,
    required DateTime correctedOccurredAt,
    required String reason,
    String? evidenceNotes,
  });

  /// Approve or deny a time correction.
  Future<void> decideCorrection({
    required String correctionId,
    required String decision,
    String? reason,
  });
}

class TimeCorrectionException implements Exception {
  const TimeCorrectionException(this.message);
  const TimeCorrectionException.offline() : message = 'Connection unavailable';

  final String message;

  @override
  String toString() => message;
}

abstract class OTRepository {
  Future<String> submitRequest({
    required String jobId,
    double? totalHours,
    String? notes,
    String? photoEventId,
  });

  /// Fetches OT requests awaiting foreman approval.
  Future<List<OTRequest>> fetchPendingRequests();

  /// Approves an OT request.
  Future<void> approveRequest(String requestId);

  /// Denies an OT request with optional reason.
  Future<void> denyRequest(String requestId, {String? reason});
}

/// A single OT request from a worker.
class OTRequest {
  const OTRequest({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.jobId,
    required this.jobName,
    required this.createdAt,
    this.totalHours,
    this.notes,
    this.status = 'pending',
  });

  final String id;
  final String workerId;
  final String workerName;
  final String jobId;
  final String jobName;
  final DateTime createdAt;
  final double? totalHours;
  final String? notes;
  final String status;

  factory OTRequest.fromJson(Map<String, dynamic> json) {
    return OTRequest(
      id: json['id'] as String,
      workerId: json['worker_id'] as String? ?? '',
      workerName: json['worker_name'] as String? ?? 'Unknown',
      jobId: json['job_id'] as String? ?? '',
      jobName: json['job_name'] as String? ?? 'Unknown job',
      createdAt: DateTime.parse(json['created_at'] as String),
      totalHours: (json['total_hours'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'pending',
    );
  }
}

enum OTRepositoryErrorType { offline, unknown }

class OTRepositoryException implements Exception {
  const OTRepositoryException._({
    required this.type,
    required this.message,
  });

  const OTRepositoryException.offline()
      : this._(
          type: OTRepositoryErrorType.offline,
          message: 'No connection available for OT request.',
        );

  const OTRepositoryException.unknown([
    String message = 'OT request could not be submitted.',
  ]) : this._(type: OTRepositoryErrorType.unknown, message: message);

  final OTRepositoryErrorType type;
  final String message;

  @override
  String toString() => 'OTRepositoryException($type): $message';
}

/// A single GPS breadcrumb sample recorded during a shift.
class Breadcrumb {
  const Breadcrumb({
    required this.id,
    required this.userId,
    required this.jobId,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    required this.recordedAt,
    required this.shiftDate,
  });

  factory Breadcrumb.fromJson(Map<String, dynamic> json) {
    return Breadcrumb(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      jobId: json['job_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      shiftDate: json['shift_date'] as String,
    );
  }

  final String id;
  final String userId;
  final String jobId;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final DateTime recordedAt;
  final String shiftDate;
}

/// Repository for GPS breadcrumb trails.
abstract class BreadcrumbRepository {
  /// Fetch breadcrumbs for a user on a given date.
  Future<List<Breadcrumb>> fetchBreadcrumbs({
    required String shiftDate,
    String? userId,
    String? jobId,
  });

  /// Upload a batch of breadcrumbs.
  Future<void> uploadBreadcrumbs(List<Map<String, dynamic>> breadcrumbs);
}

class BreadcrumbRepositoryException implements Exception {
  const BreadcrumbRepositoryException(this.message);
  final String message;

  @override
  String toString() => 'BreadcrumbRepositoryException: $message';
}

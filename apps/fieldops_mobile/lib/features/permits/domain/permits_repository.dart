/// Repository contract for the mobile permit-gating flow.
///
/// The backend exposes a read-only `permits` edge function with action
/// `check_active`. It tells us whether [jobId] requires a work permit and
/// whether an active one exists. The mobile clock-in flow uses this as a
/// first gate before the safety checklist.
abstract class PermitsRepository {
  /// Asks the server whether [jobId] requires a permit and whether one is
  /// active. Implementations should be idempotent; no idempotency key is
  /// needed because the call is read-only.
  Future<PermitCheckResult> checkActive({required String jobId});
}

/// Decoded payload of `permits` action `check_active`.
class PermitCheckResult {
  const PermitCheckResult({
    required this.required,
    this.requiredType,
    this.activePermit,
  });

  /// Whether this job requires a permit at all.
  final bool required;

  /// Server-defined permit-type identifier (e.g. `hv_electrical`). Null when
  /// [required] is false.
  final String? requiredType;

  /// The currently active permit covering this job, if any.
  final ActivePermit? activePermit;
}

/// Minimal view of an active permit returned by the server. The mobile app
/// only needs the identifying fields for display / debugging — issuance and
/// editing flows live elsewhere.
class ActivePermit {
  const ActivePermit({
    required this.id,
    required this.permitNumber,
    required this.permitType,
    this.expiresAt,
  });

  final String id;
  final String permitNumber;
  final String permitType;
  final DateTime? expiresAt;

  factory ActivePermit.fromJson(Map<String, dynamic> json) {
    final rawExpires = json['expires_at'];
    DateTime? expires;
    if (rawExpires is String && rawExpires.isNotEmpty) {
      expires = DateTime.tryParse(rawExpires);
    }
    return ActivePermit(
      id: json['id'] as String? ?? '',
      permitNumber: json['permit_number'] as String? ?? '',
      permitType: json['permit_type'] as String? ?? '',
      expiresAt: expires,
    );
  }
}

/// Typed exception emitted by [PermitsRepository] implementations.
///
/// The clock-in gate distinguishes [PermitsRepositoryExceptionKind.offline]
/// (graceful fallback — let the worker proceed; server will re-enforce) from
/// [PermitsRepositoryExceptionKind.unknown] (hard error — block clock-in
/// with a retry prompt).
class PermitsRepositoryException implements Exception {
  const PermitsRepositoryException(this.message, this.kind);

  const PermitsRepositoryException.offline()
      : message = 'No connection available.',
        kind = PermitsRepositoryExceptionKind.offline;

  const PermitsRepositoryException.unknown(this.message)
      : kind = PermitsRepositoryExceptionKind.unknown;

  final String message;
  final PermitsRepositoryExceptionKind kind;

  bool get isOffline => kind == PermitsRepositoryExceptionKind.offline;

  @override
  String toString() => 'PermitsRepositoryException($kind): $message';
}

enum PermitsRepositoryExceptionKind { offline, unknown }

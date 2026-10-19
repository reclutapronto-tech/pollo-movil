import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Possible user roles in the FieldOps system.
enum UserRole { worker, foreman, supervisor, admin }

/// Provides the current user's role from Supabase user metadata.
///
/// Reads `app_metadata['role']` (set via admin API or database trigger).
/// Falls back to [UserRole.worker] when no metadata is present.
final userRoleProvider = Provider<UserRole>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return UserRole.worker;

  final role = user.appMetadata['role'] as String? ??
      user.userMetadata?['role'] as String? ??
      'worker';

  return switch (role) {
    'foreman' => UserRole.foreman,
    'supervisor' => UserRole.supervisor,
    'admin' => UserRole.admin,
    _ => UserRole.worker,
  };
});

/// Convenience: true when the user has foreman-level access or above.
extension UserRoleX on UserRole {
  bool get canManageCrew =>
      this == UserRole.foreman ||
      this == UserRole.supervisor ||
      this == UserRole.admin;

  /// True only for owner-level admins who can change company-scoped
  /// settings like PTO allocations, feature flags, etc. Mirrors web
  /// `isManagementRole()`.
  bool get canAdministerCompany => this == UserRole.admin;
}

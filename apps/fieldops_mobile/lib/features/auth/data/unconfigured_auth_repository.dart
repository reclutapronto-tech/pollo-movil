import 'package:fieldops_mobile/features/auth/domain/auth_repository.dart';

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  @override
  bool get isAuthenticated => false;

  @override
  String? get currentUserEmail => null;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY. Configure dart-defines before trying to sign in.',
    );
  }

  @override
  Future<void> signOut() async {}
}

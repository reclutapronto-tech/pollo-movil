import 'package:fieldops_mobile/features/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get isAuthenticated => _client.auth.currentSession != null;

  @override
  String? get currentUserEmail => _client.auth.currentUser?.email;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.session == null) {
      throw StateError('Sign-in did not return a session.');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

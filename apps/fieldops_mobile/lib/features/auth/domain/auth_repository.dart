abstract interface class AuthRepository {
  bool get isAuthenticated;
  String? get currentUserEmail;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

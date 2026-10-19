import 'dart:async';

import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  StreamSubscription<AuthState>? _authSub;

  @override
  SessionState build() {
    final repository = ref.watch(authRepositoryProvider);
    final environment = ref.watch(fieldOpsEnvironmentProvider);

    // Keep session in sync with Supabase's internal auth state changes.
    // This catches token refresh failures (e.g. password changed elsewhere)
    // and automatically returns the user to the login screen.
    //
    // Only subscribe when Supabase is actually initialized — accessing
    // `Supabase.instance.client` without `Supabase.initialize()` throws.
    _authSub?.cancel();
    if (environment.isConfigured) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        refresh();
      });
    }
    ref.onDispose(() => _authSub?.cancel());

    return SessionState(
      isAuthenticated: repository.isAuthenticated,
      email: repository.currentUserEmail,
    );
  }

  void refresh() {
    final repository = ref.read(authRepositoryProvider);
    state = SessionState(
      isAuthenticated: repository.isAuthenticated,
      email: repository.currentUserEmail,
    );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    refresh();
  }
}

class SessionState {
  const SessionState({required this.isAuthenticated, this.email});

  final bool isAuthenticated;
  final String? email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          isAuthenticated == other.isAuthenticated &&
          email == other.email;

  @override
  int get hashCode => Object.hash(isAuthenticated, email);
}

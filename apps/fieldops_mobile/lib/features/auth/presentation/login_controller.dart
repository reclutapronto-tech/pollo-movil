import 'package:fieldops_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:fieldops_mobile/features/auth/presentation/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final loginControllerProvider = AsyncNotifierProvider<LoginController, void>(
  LoginController.new,
);

class LoginController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authRepositoryProvider)
          .signInWithPassword(email: email.trim(), password: password);
      ref.read(sessionControllerProvider.notifier).refresh();
    });
  }

  void clearError() {
    if (state.hasError) {
      state = const AsyncData(null);
    }
  }
}

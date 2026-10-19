import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// How long the app can be inactive before requiring biometric re-auth.
const _inactivityTimeout = Duration(minutes: 5);

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

class AppLockController extends Notifier<AppLockState> {
  Timer? _inactivityTimer;

  @override
  AppLockState build() {
    ref.onDispose(() => _inactivityTimer?.cancel());
    return const AppLockState();
  }

  /// Call when the user interacts with the app (tap, scroll, etc.).
  void recordActivity() {
    if (!state.isEnabled) return;
    _resetTimer();
  }

  /// Enable the lock. Call after login.
  void enable() {
    state = state.copyWith(isEnabled: true, isLocked: false);
    _resetTimer();
  }

  /// Disable the lock. Call on logout.
  void disable() {
    _inactivityTimer?.cancel();
    state = const AppLockState();
  }

  /// Lock the app immediately (e.g. when backgrounded).
  void lock() {
    if (!state.isEnabled) return;
    _inactivityTimer?.cancel();
    state = state.copyWith(isLocked: true);
  }

  /// Attempt biometric authentication. Returns true on success.
  Future<bool> authenticate() async {
    state = state.copyWith(isAuthenticating: true, authError: null);

    try {
      final auth = LocalAuthentication();
      final isAvailable = await auth.isDeviceSupported();

      if (!isAvailable) {
        // Device has no biometric hardware — unlock without prompt.
        state = state.copyWith(isLocked: false, isAuthenticating: false);
        _resetTimer();
        return true;
      }

      final canCheck = await auth.canCheckBiometrics;
      if (!canCheck) {
        state = state.copyWith(isLocked: false, isAuthenticating: false);
        _resetTimer();
        return true;
      }

      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Verify your identity to continue using FieldOps',
        options: const AuthenticationOptions(
          biometricOnly: false, // Allow PIN/pattern fallback
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        state = state.copyWith(isLocked: false, isAuthenticating: false);
        _resetTimer();
        return true;
      } else {
        state = state.copyWith(
          isAuthenticating: false,
          authError: 'Authentication failed. Try again.',
        );
        return false;
      }
    } on Exception catch (e) {
      debugPrint('Biometric auth error: $e');
      state = state.copyWith(
        isAuthenticating: false,
        authError: 'Authentication unavailable.',
      );
      return false;
    }
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      if (state.isEnabled) lock();
    });
  }
}

class AppLockState {
  const AppLockState({
    this.isEnabled = false,
    this.isLocked = false,
    this.isAuthenticating = false,
    this.authError,
  });

  final bool isEnabled;
  final bool isLocked;
  final bool isAuthenticating;
  final String? authError;

  AppLockState copyWith({
    bool? isEnabled,
    bool? isLocked,
    bool? isAuthenticating,
    Object? authError = _sentinel,
  }) {
    return AppLockState(
      isEnabled: isEnabled ?? this.isEnabled,
      isLocked: isLocked ?? this.isLocked,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      authError:
          authError == _sentinel ? this.authError : authError as String?,
    );
  }
}

const _sentinel = Object();

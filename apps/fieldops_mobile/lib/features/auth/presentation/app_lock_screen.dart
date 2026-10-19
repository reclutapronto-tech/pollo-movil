import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/auth/presentation/app_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen overlay shown when the app is locked due to inactivity
/// or being backgrounded. Prompts biometric / PIN re-authentication.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-prompt biometric on mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appLockControllerProvider.notifier).authenticate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: palette.slate,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: palette.signal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 48,
                    color: palette.signal,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Session Locked',
                  style: textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Verify your identity to continue',
                  style: textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
                ),

                if (lockState.authError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                    ),
                    child: Text(
                      lockState.authError!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.danger,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                SizedBox(
                  width: 200,
                  child: ElevatedButton.icon(
                    onPressed: lockState.isAuthenticating
                        ? null
                        : () => ref
                            .read(appLockControllerProvider.notifier)
                            .authenticate(),
                    icon: lockState.isAuthenticating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.fingerprint_rounded),
                    label: Text(
                      lockState.isAuthenticating
                          ? 'Verifying...'
                          : 'Unlock',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

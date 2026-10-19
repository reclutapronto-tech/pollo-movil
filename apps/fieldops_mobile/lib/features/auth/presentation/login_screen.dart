import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/auth/presentation/login_controller.dart';
import 'package:fieldops_mobile/features/auth/presentation/widgets/error_banner.dart';
import 'package:fieldops_mobile/features/auth/presentation/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _obscurePassword = true;
  bool _rememberEmail = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    try {
      final saved = await _storage.read(key: 'saved_email');
      if (!mounted || saved == null) return;
      setState(() {
        _emailController.text = saved;
        _rememberEmail = true;
      });
    } on PlatformException catch (e, stack) {
      debugPrint('Secure storage read failed (saved_email): $e\n$stack');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    ref.read(loginControllerProvider.notifier).clearError();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref.read(loginControllerProvider.notifier).signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted) return;

    try {
      if (_rememberEmail) {
        await _storage.write(key: 'saved_email', value: _emailController.text.trim());
      } else {
        await _storage.delete(key: 'saved_email');
      }
    } on PlatformException catch (e, stack) {
      debugPrint('Secure storage write failed (saved_email): $e\n$stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final isLoading = loginState.isLoading;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [palette.slate, const Color(0xFF233A4A), palette.canvas],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            StatusChip(
                              label: 'Worker login',
                              color: palette.signal,
                              textColor: palette.slate,
                            ),
                            StatusChip(
                              label: 'Proof-first',
                              color:
                                  palette.success.withValues(alpha: 0.14),
                              textColor: palette.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Clock in fast.\nProve the work.\nKeep moving.',
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Secure login, zero clutter, and a straight path into the worker flow.',
                          style: textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 28),
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                label: 'Email address input',
                                textField: true,
                                child: TextFormField(
                                  controller: _emailController,
                                  keyboardType:
                                      TextInputType.emailAddress,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    hintText: 'you@company.com',
                                    prefixIcon:
                                        Icon(Icons.email_outlined),
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty) {
                                      return 'Email is required.';
                                    }
                                    if (!email.contains('@')) {
                                      return 'Enter a valid email address.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberEmail,
                                    onChanged: (_) => setState(() => _rememberEmail = !_rememberEmail),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _rememberEmail = !_rememberEmail),
                                    child: Text(
                                      'Remember my email',
                                      style: textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Semantics(
                                label: 'Password input',
                                textField: true,
                                child: TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    hintText: 'Enter your password',
                                    prefixIcon:
                                        const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                      ),
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () {
                                        setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        );
                                      },
                                    ),
                                  ),
                                  validator: (value) {
                                    if ((value ?? '').isEmpty) {
                                      return 'Password is required.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              if (loginState.hasError) ...[
                                const SizedBox(height: 16),
                                ErrorBanner(
                                  message:
                                      _formatError(loginState.error),
                                ),
                              ],
                              const SizedBox(height: 24),
                              Semantics(
                                button: true,
                                label: isLoading
                                    ? 'Signing in'
                                    : 'Sign in to worker app',
                                child: ElevatedButton(
                                  onPressed:
                                      isLoading ? null : _submit,
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                          ),
                                        )
                                      : const Text(
                                          'Sign in to worker app'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatError(Object? error) {
    if (error is StateError) {
      return error.message;
    }
    return 'Sign-in failed. Check your credentials and connection, then try again.';
  }
}

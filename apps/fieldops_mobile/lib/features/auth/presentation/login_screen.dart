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
                        Center(
                          child: Image.asset(
                            'assets/branding/pollo-movil.png',
                            width: 176,
                            height: 176,
                            fit: BoxFit.contain,
                            semanticLabel: 'Logotipo oficial de El Pollo Móvil',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            StatusChip(
                              label: 'Acceso de equipo',
                              color: palette.signal,
                              textColor: palette.slate,
                            ),
                            StatusChip(
                              label: 'Operación de restaurante',
                              color:
                                  palette.success.withValues(alpha: 0.14),
                              textColor: palette.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Coordina el turno.\nResuelve el trabajo.\nHaz el relevo.',
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Acceso seguro a las actividades, inspecciones e incidencias de tu sucursal.',
                          style: textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 28),
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                    label: 'Campo de correo electrónico',
                                textField: true,
                                child: TextFormField(
                                  controller: _emailController,
                                  keyboardType:
                                      TextInputType.emailAddress,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Correo electrónico',
                                    hintText: 'tu@empresa.com',
                                    prefixIcon:
                                        Icon(Icons.email_outlined),
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty) {
                                      return 'El correo es obligatorio.';
                                    }
                                    if (!email.contains('@')) {
                                      return 'Escribe un correo válido.';
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
                                      'Recordar mi correo',
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
                                    labelText: 'Contraseña',
                                    hintText: 'Escribe tu contraseña',
                                    prefixIcon:
                                        const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                      ),
                                      tooltip: _obscurePassword
                                          ? 'Mostrar contraseña'
                                          : 'Ocultar contraseña',
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
                                      return 'La contraseña es obligatoria.';
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
                                    ? 'Iniciando sesión'
                                    : 'Iniciar sesión en Pollo Móvil',
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
                                          'Iniciar sesión'),
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

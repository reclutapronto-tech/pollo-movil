import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ConfigurationRequiredScreen extends StatelessWidget {
  const ConfigurationRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [palette.canvas, Colors.white, palette.canvas],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minHeight = constraints.maxHeight > 48
                  ? constraints.maxHeight - 48
                  : 0.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.settings_suggest_rounded,
                              size: 40,
                              color: palette.signal,
                              semanticLabel: 'Configuration needed',
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Mobile app needs Supabase config',
                              style: textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Usa el lanzador local para conectar Android con Supabase. En un teléfono por USB, configura ADB reverse; '
                              'las conexiones HTTP solo se permiten a los destinos locales de desarrollo.',
                              style: textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 20),
                            Semantics(
                              label:
                                  'Comandos para conectar la app a Supabase local',
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: palette.slate,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: SelectableText(
                                  'Emulador Android:\n'
                                  '.\\scripts\\run-pollo-movil-local.ps1 -App android\n\n'
                                  'Teléfono Android por USB:\n'
                                  '.\\scripts\\run-pollo-movil-local.ps1 -App android -MobileSupabaseUrl http://localhost:54321\n\n'
                                  'iOS Simulator (macOS):\n'
                                  'flutter run --dart-define=SUPABASE_URL=http://127.0.0.1:54321\n'
                                  '  --dart-define=SUPABASE_ANON_KEY=<clave-publica-local>',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

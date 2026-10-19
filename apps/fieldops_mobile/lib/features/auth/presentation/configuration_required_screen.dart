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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                        'Run the app with dart-defines so login can talk to the local backend.',
                        style: textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      Semantics(
                        label: 'Terminal command to configure the app',
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: palette.slate,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: SelectableText(
                            'flutter run \\\n'
                            '  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \\\n'
                            '  --dart-define=SUPABASE_ANON_KEY=<anon-key>',
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
        ),
      ),
    );
  }
}

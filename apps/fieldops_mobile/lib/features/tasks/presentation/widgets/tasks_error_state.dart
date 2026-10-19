import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class TasksErrorState extends StatelessWidget {
  const TasksErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Error: $message',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 36, color: palette.danger,
                    semanticLabel: 'Error'),
                const SizedBox(height: 12),
                Text('Tasks unavailable', style: textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(message, style: textTheme.bodyMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 18),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/jobs/domain/jobs_repository.dart';
import 'package:flutter/material.dart';

class JobsErrorState extends StatelessWidget {
  const JobsErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final JobsRepositoryException error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final title = error.isOffline ? 'You are offline' : 'Jobs are unavailable';
    final copy = error.isOffline
        ? 'Saved credentials are intact, but assigned jobs could not refresh right now.'
        : error.message;

    return Center(
      child: Semantics(
        liveRegion: true,
        label: '$title. $copy',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 36,
                  color: palette.danger,
                  semanticLabel: 'Connection error',
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  copy,
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Retry jobs'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class JobsEmptyState extends StatelessWidget {
  const JobsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: palette.steel,
              semanticLabel: 'No jobs',
            ),
            const SizedBox(height: 12),
            Text('No assigned jobs yet', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Pull to refresh after a supervisor assigns work.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class TasksEmptyState extends StatelessWidget {
  const TasksEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.checklist_rounded, size: 40, color: palette.steel,
                semanticLabel: 'No tasks'),
            const SizedBox(height: 12),
            Text('No tasks for this job', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tasks will appear here once a supervisor adds them.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

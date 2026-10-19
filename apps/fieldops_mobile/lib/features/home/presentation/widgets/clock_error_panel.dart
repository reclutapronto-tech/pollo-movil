import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:flutter/material.dart';

class ClockErrorPanel extends StatelessWidget {
  const ClockErrorPanel({super.key, required this.state});

  final ClockInState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: '${state.errorTitle}. ${state.errorMessage}',
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surfaceWhite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: palette.danger,
              semanticLabel: 'Error',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.errorTitle ?? '', style: textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(state.errorMessage ?? '', style: textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

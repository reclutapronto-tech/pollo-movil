import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      liveRegion: true,
      label: 'Error: $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.danger.withValues(alpha: 0.35)),
        ),
        child: Text(
          message,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: palette.danger),
        ),
      ),
    );
  }
}

import 'package:fieldops_mobile/features/schedule/presentation/worker_schedule_screen.dart';
import 'package:flutter/material.dart';

/// Schedule tab — thin wrapper around the existing [WorkerScheduleScreen].
///
/// This keeps the full schedule implementation in its own widget while
/// allowing the tab to be embedded in the [MainShell] IndexedStack.
class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkerScheduleScreen();
  }
}

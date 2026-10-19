import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_capture_screen.dart';
import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/history/presentation/history_tab.dart';
import 'package:fieldops_mobile/features/home/presentation/home_tab.dart';
import 'package:fieldops_mobile/features/jobs/presentation/jobs_tab.dart';
import 'package:fieldops_mobile/features/more/presentation/more_tab.dart';
import 'package:fieldops_mobile/features/schedule/presentation/schedule_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global navigator key for deep-link navigation from push notifications.
final mainShellNavigatorKey = GlobalKey<NavigatorState>();

/// Provider tracking the active bottom nav tab index.
final activeTabIndexProvider = NotifierProvider<_TabIndexNotifier, int>(
  _TabIndexNotifier.new,
);

class _TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

/// Main app shell with 5-tab BottomNavigationBar.
///
/// Preserves tab state via [IndexedStack] so scrolling position, form state,
/// and provider subscriptions survive tab switches.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, this.email});

  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(activeTabIndexProvider);
    final clockState = ref.watch(clockControllerProvider);
    final palette = context.palette;

    // Surface the "saved offline" hint from the clock controller as a
    // one-shot SnackBar. The controller publishes the string when a clock
    // event falls through to the outbox; we ack immediately so it fires once.
    ref.listen<ClockState>(clockControllerProvider, (previous, next) {
      final msg = next.offlineQueuedMessage;
      if (msg == null) return;
      if (previous?.offlineQueuedMessage == msg) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      }
      ref
          .read(clockControllerProvider.notifier)
          .acknowledgeOfflineQueuedMessage();
    });

    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: [
          HomeTab(email: email),
          const JobsTab(),
          const ScheduleTab(),
          const HistoryTab(),
          MoreTab(email: email),
        ],
      ),
      bottomNavigationBar: _FieldOpsBottomNav(
        currentIndex: tabIndex,
        palette: palette,
        onTap: (index) {
          HapticFeedback.selectionClick();
          ref.read(activeTabIndexProvider.notifier).setIndex(index);
        },
      ),
      // Camera FAB when clocked in — fastest path to proof photo
      floatingActionButton: clockState.isClockedIn
          ? _CameraFAB(
              jobId: clockState.activeJobId!,
              jobName: clockState.activeJobName ?? '',
              palette: palette,
            )
          : null,
    );
  }
}

class _FieldOpsBottomNav extends StatelessWidget {
  const _FieldOpsBottomNav({
    required this.currentIndex,
    required this.palette,
    required this.onTap,
  });

  final int currentIndex;
  final FieldOpsPalette palette;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.border, width: 0.5),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        backgroundColor: palette.surfaceWhite,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.signal.withValues(alpha: 0.12),
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: palette.steel),
            selectedIcon: Icon(Icons.home_rounded, color: palette.signal),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline_rounded, color: palette.steel),
            selectedIcon: Icon(Icons.work_rounded, color: palette.signal),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined, color: palette.steel),
            selectedIcon:
                Icon(Icons.calendar_month_rounded, color: palette.signal),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: palette.steel),
            selectedIcon: Icon(Icons.history_rounded, color: palette.signal),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded, color: palette.steel),
            selectedIcon: Icon(Icons.more_horiz_rounded, color: palette.signal),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _CameraFAB extends StatelessWidget {
  const _CameraFAB({
    required this.jobId,
    required this.jobName,
    required this.palette,
  });

  final String jobId;
  final String jobName;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take proof photo for $jobName',
      child: FloatingActionButton(
        backgroundColor: palette.signal,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () async {
          await HapticFeedback.mediumImpact();
          if (!context.mounted) return;
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final result = await navigator.push<PhotoCaptureResult?>(
            MaterialPageRoute<PhotoCaptureResult?>(
              builder: (_) => CameraCaptureScreen(
                jobId: jobId,
                jobName: jobName,
                allowSaveForLater: true,
              ),
            ),
          );

          if (result == null) return;
          final message = result.isSavedForLater
              ? 'Photo saved on device.'
              : 'Photo uploaded for $jobName.';
          messenger.showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
        child: const Icon(Icons.camera_alt_rounded, size: 28),
      ),
    );
  }
}

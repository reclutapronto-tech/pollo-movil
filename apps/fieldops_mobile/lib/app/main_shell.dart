import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_clock_tab.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_more_tab.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_ops_tab.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global navigator key for deep-link navigation from push notifications.
final mainShellNavigatorKey = GlobalKey<NavigatorState>();

final activeTabKeyProvider = NotifierProvider<_TabKeyNotifier, String>(
  _TabKeyNotifier.new,
);

class _TabKeyNotifier extends Notifier<String> {
  @override
  String build() => 'shift';

  void setTab(String key) => state = key;
}

/// Pollo Móvil's task-focused, Spanish-first navigation.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, this.email});

  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final activeTabKey = ref.watch(activeTabKeyProvider);
    final branches = ref
        .watch(restaurantBranchesProvider)
        .maybeWhen(data: (items) => items, orElse: () => <OpsJson>[]);
    final selectedBranchId = ref.watch(restaurantSelectedBranchProvider);
    final clockBranch = branches.isEmpty
        ? null
        : branches.firstWhere(
            (branch) => branch['id'] == selectedBranchId,
            orElse: () => branches.first,
          );
    final accessRole = clockBranch?['access_role'] as String?;
    final isManager = accessRole == 'admin' || accessRole == 'supervisor';
    // Unknown/loading roles default to the least-privileged worker navigation.
    final workerMode = !isManager;
    final showClock = clockBranch?['enable_time_clock'] == true;
    final destinationKeys = workerMode
        ? <String>[
            'worker_tasks',
            'worker_notices',
            'worker_shift',
            'worker_record',
          ]
        : <String>[
            'shift',
            'waste',
            'incidents',
            'handoff',
            if (showClock) 'clock',
            'more',
          ];
    final children = workerMode
        ? <Widget>[const _WorkerFocusTab()]
        : <Widget>[
            const RestaurantOpsTab(section: RestaurantOpsSection.shift),
            const RestaurantOpsTab(section: RestaurantOpsSection.waste),
            const RestaurantOpsTab(section: RestaurantOpsSection.incidents),
            const RestaurantOpsTab(section: RestaurantOpsSection.handoff),
            if (showClock)
              RestaurantClockTab(
                branchId: clockBranch?['id'] as String,
                branchName:
                    clockBranch?['name'] as String? ??
                    l10n.restaurantOpsBranchFallback,
                requireGps: clockBranch?['require_gps_for_time_clock'] == true,
              ),
            RestaurantMoreTab(email: email),
          ];
    final requestedTabKey = workerMode
        ? (activeTabKey == 'shift' ? 'worker_tasks' : activeTabKey)
        : (activeTabKey.startsWith('worker_') ? 'shift' : activeTabKey);
    final effectiveTabKey = destinationKeys.contains(requestedTabKey)
        ? requestedTabKey
        : (workerMode ? 'worker_tasks' : 'shift');
    final safeTabIndex = destinationKeys.indexOf(effectiveTabKey);
    final palette = context.palette;

    return Scaffold(
      body: IndexedStack(
        index: workerMode ? 0 : safeTabIndex,
        children: children,
      ),
      bottomNavigationBar: _PolloBottomNav(
        currentIndex: safeTabIndex,
        palette: palette,
        destinationKeys: destinationKeys,
        onTap: (index) {
          HapticFeedback.selectionClick();
          ref
              .read(activeTabKeyProvider.notifier)
              .setTab(destinationKeys[index]);
        },
      ),
    );
  }
}

class _WorkerFocusTab extends ConsumerWidget {
  const _WorkerFocusTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = switch (ref.watch(activeTabKeyProvider)) {
      'worker_notices' => 'notices',
      'worker_shift' => 'shift',
      'worker_record' => 'record',
      _ => 'tasks',
    };
    return RestaurantOpsTab(
      section: RestaurantOpsSection.shift,
      workerFocus: focus,
    );
  }
}

class _PolloBottomNav extends StatelessWidget {
  const _PolloBottomNav({
    required this.currentIndex,
    required this.palette,
    required this.destinationKeys,
    required this.onTap,
  });

  final int currentIndex;
  final FieldOpsPalette palette;
  final List<String> destinationKeys;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border, width: 0.5)),
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
          for (final key in destinationKeys) _destination(key, l10n),
        ],
      ),
    );
  }

  NavigationDestination _destination(String key, AppLocalizations l10n) {
    final worker = switch (key) {
      'worker_tasks' => (
        Icons.assignment_outlined,
        Icons.assignment_rounded,
        'Mis tareas',
      ),
      'worker_notices' => (
        Icons.notifications_outlined,
        Icons.notifications_rounded,
        'Avisos',
      ),
      'worker_shift' => (
        Icons.access_time_rounded,
        Icons.access_time_filled_rounded,
        'Mi turno',
      ),
      'worker_record' => (
        Icons.add_task_outlined,
        Icons.add_task_rounded,
        'Registrar',
      ),
      _ => null,
    };
    if (worker != null) {
      return NavigationDestination(
        icon: Icon(worker.$1, color: palette.steel),
        selectedIcon: Icon(worker.$2, color: palette.signal),
        label: worker.$3,
      );
    }
    final manager = switch (key) {
      'shift' => (
        Icons.assignment_outlined,
        Icons.assignment_rounded,
        l10n.restaurantOpsShiftTitle,
      ),
      'waste' => (
        Icons.delete_outline_rounded,
        Icons.delete_rounded,
        l10n.restaurantOpsWasteTitle,
      ),
      'incidents' => (
        Icons.report_outlined,
        Icons.report_rounded,
        l10n.restaurantOpsIncidentsTitle,
      ),
      'handoff' => (
        Icons.swap_horiz_rounded,
        Icons.swap_horiz_rounded,
        l10n.restaurantOpsHandoffTitle,
      ),
      'clock' => (
        Icons.access_time_rounded,
        Icons.access_time_filled_rounded,
        l10n.restaurantClockTitle,
      ),
      _ => (
        Icons.more_horiz_rounded,
        Icons.more_horiz_rounded,
        l10n.restaurantMoreTitle,
      ),
    };
    return NavigationDestination(
      icon: Icon(manager.$1, color: palette.steel),
      selectedIcon: Icon(manager.$2, color: palette.signal),
      label: manager.$3,
    );
  }
}

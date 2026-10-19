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
    final branches = ref.watch(restaurantBranchesProvider).maybeWhen(
          data: (items) => items,
          orElse: () => <OpsJson>[],
        );
    final selectedBranchId = ref.watch(restaurantSelectedBranchProvider);
    final clockBranch = branches.isEmpty
        ? null
        : branches.firstWhere(
            (branch) => branch['id'] == selectedBranchId,
            orElse: () => branches.first,
          );
    final showClock = clockBranch?['enable_time_clock'] == true;
    final destinationKeys = <String>[
      'shift', 'waste', 'incidents', 'handoff',
      if (showClock) 'clock',
      'more',
    ];
    final children = <Widget>[
      const RestaurantOpsTab(section: RestaurantOpsSection.shift),
      const RestaurantOpsTab(section: RestaurantOpsSection.waste),
      const RestaurantOpsTab(section: RestaurantOpsSection.incidents),
      const RestaurantOpsTab(section: RestaurantOpsSection.handoff),
      if (showClock)
        RestaurantClockTab(
          branchId: clockBranch?['id'] as String,
          branchName: clockBranch?['name'] as String? ?? l10n.restaurantOpsBranchFallback,
          requireGps: clockBranch?['require_gps_for_time_clock'] == true,
        ),
      RestaurantMoreTab(email: email),
    ];
    final effectiveTabKey = destinationKeys.contains(activeTabKey) ? activeTabKey : 'more';
    final safeTabIndex = destinationKeys.indexOf(effectiveTabKey);
    final palette = context.palette;

    return Scaffold(
      body: IndexedStack(
        index: safeTabIndex,
        children: children,
      ),
      bottomNavigationBar: _PolloBottomNav(
        currentIndex: safeTabIndex,
        palette: palette,
        showClock: showClock,
        onTap: (index) {
          HapticFeedback.selectionClick();
          ref.read(activeTabKeyProvider.notifier).setTab(destinationKeys[index]);
        },
      ),
    );
  }
}

class _PolloBottomNav extends StatelessWidget {
  const _PolloBottomNav({
    required this.currentIndex,
    required this.palette,
    required this.showClock,
    required this.onTap,
  });

  final int currentIndex;
  final FieldOpsPalette palette;
  final bool showClock;
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
            NavigationDestination(
              icon: Icon(Icons.assignment_outlined, color: palette.steel),
              selectedIcon: Icon(Icons.assignment_rounded, color: palette.signal),
              label: l10n.restaurantOpsShiftTitle,
            ),
            NavigationDestination(
              icon: Icon(Icons.delete_outline_rounded, color: palette.steel),
              selectedIcon: Icon(Icons.delete_rounded, color: palette.signal),
              label: l10n.restaurantOpsWasteTitle,
            ),
            NavigationDestination(
              icon: Icon(Icons.report_outlined, color: palette.steel),
              selectedIcon: Icon(Icons.report_rounded, color: palette.signal),
              label: l10n.restaurantOpsIncidentsTitle,
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_rounded, color: palette.steel),
              selectedIcon: Icon(Icons.swap_horiz_rounded, color: palette.signal),
              label: l10n.restaurantOpsHandoffTitle,
            ),
            if (showClock)
              NavigationDestination(
                icon: Icon(Icons.access_time_rounded, color: palette.steel),
                selectedIcon: Icon(Icons.access_time_filled_rounded, color: palette.signal),
                label: l10n.restaurantClockTitle,
              ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded, color: palette.steel),
              selectedIcon: Icon(Icons.more_horiz_rounded, color: palette.signal),
              label: l10n.restaurantMoreTitle,
            ),
          ],
        ),
    );
  }
}

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/core/notifications/notification_service.dart';
import 'package:fieldops_mobile/features/auth/presentation/session_controller.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantMoreTab extends ConsumerStatefulWidget {
  const RestaurantMoreTab({super.key, this.email});

  final String? email;

  @override
  ConsumerState<RestaurantMoreTab> createState() => _RestaurantMoreTabState();
}

class _RestaurantMoreTabState extends ConsumerState<RestaurantMoreTab> {
  bool _pushEnabled = false;
  bool _pushLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPushPreference();
  }

  Future<void> _loadPushPreference() async {
    final service = ref.read(notificationServiceProvider);
    var enabled = false;
    try {
      enabled = await service.isEnabled;
    } catch (_) {
      // A local preference store failure must not block operational screens.
    }
    if (mounted)
      setState(() {
        _pushEnabled = enabled;
        _pushLoading = false;
      });
  }

  Future<void> _setPushEnabled(bool enabled) async {
    final service = ref.read(notificationServiceProvider);
    setState(() => _pushLoading = true);
    var saved = false;
    try {
      saved = await service.setEnabled(enabled);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _pushEnabled = saved && enabled;
      _pushLoading = false;
    });
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.restaurantPushEnableFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = context.palette;
    final pushService = ref.watch(notificationServiceProvider);
    final pushAvailable = pushService.isAvailable;
    final accountLabel = widget.email?.isNotEmpty == true
        ? widget.email![0].toUpperCase()
        : 'P';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.restaurantMoreTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(accountLabel)),
              title: Text(widget.email ?? l10n.restaurantAccount),
              subtitle: Text(l10n.restaurantAssignedBranchAccess),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.restaurantMoreDescription),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile.adaptive(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(l10n.restaurantNotificationsThisDevice),
              subtitle: Text(
                pushAvailable
                    ? l10n.restaurantPushOperationalUpdates
                    : l10n.restaurantPushRequiresSetup,
              ),
              value: pushAvailable && _pushEnabled,
              onChanged: pushAvailable && !_pushLoading
                  ? _setPushEnabled
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.danger,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(l10n.signOut),
                  content: Text(l10n.restaurantSignOutPendingEvents),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(l10n.signOut),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(sessionControllerProvider.notifier).signOut();
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(l10n.signOut),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              l10n.restaurantOperationalAppLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.steel),
            ),
          ),
        ],
      ),
    );
  }
}

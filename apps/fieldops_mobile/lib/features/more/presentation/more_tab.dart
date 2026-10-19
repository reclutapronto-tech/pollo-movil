import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/auth/domain/user_role.dart';
import 'package:fieldops_mobile/features/auth/presentation/session_controller.dart';
import 'package:fieldops_mobile/features/expenses/presentation/expense_history_screen.dart';
import 'package:fieldops_mobile/features/foreman/presentation/crew_clock_screen.dart';
import 'package:fieldops_mobile/features/more/presentation/help_screen.dart';
import 'package:fieldops_mobile/features/time_corrections/presentation/time_correction_screen.dart';
import 'package:fieldops_mobile/features/more/presentation/profile_screen.dart';
import 'package:fieldops_mobile/features/more/presentation/settings_screen.dart';
import 'package:fieldops_mobile/features/pto/presentation/pto_allocations_screen.dart';
import 'package:fieldops_mobile/features/pto/presentation/pto_request_screen.dart';
import 'package:fieldops_mobile/features/schedule/presentation/foreman_schedule_screen.dart';
import 'package:fieldops_mobile/features/timecards/presentation/timecards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// More tab — secondary actions, profile, settings, and support.
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key, this.email});

  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final role = ref.watch(userRoleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile header
          _ProfileHeader(email: email, palette: palette, textTheme: textTheme),
          const SizedBox(height: 24),

          // Menu items
          _MenuSection(
            title: 'Work',
            items: [
              if (role.canManageCrew)
                _MenuItem(
                  icon: Icons.groups_rounded,
                  title: 'Crew Schedule',
                  subtitle: 'Reorder today\'s crew shifts on-site',
                  color: const Color(0xFF2563EB),
                  onTap: () =>
                      _push(context, const ForemanScheduleScreen()),
                ),
              if (role.canManageCrew)
                _MenuItem(
                  icon: Icons.login_rounded,
                  title: 'Crew Clock-In',
                  subtitle: 'Clock crew members in or out on their behalf',
                  color: const Color(0xFF0891B2),
                  onTap: () => _push(context, const CrewClockScreen()),
                ),
              if (role.canManageCrew)
                _MenuItem(
                  icon: Icons.edit_calendar_rounded,
                  title: 'Time Corrections',
                  subtitle: 'Review and approve clock time adjustments',
                  color: const Color(0xFFD97706),
                  onTap: () => _push(context, const TimeCorrectionScreen()),
                ),
              _MenuItem(
                icon: Icons.beach_access_rounded,
                title: 'Time Off (PTO)',
                subtitle: 'Request vacation, sick, or personal time',
                color: const Color(0xFF7C3AED),
                onTap: () => _push(context, const PTORequestScreen()),
              ),
              _MenuItem(
                icon: Icons.receipt_long_rounded,
                title: 'My Expenses',
                subtitle: 'View submitted receipts and status',
                color: palette.signal,
                onTap: () => _push(context, const ExpenseHistoryScreen()),
              ),
              _MenuItem(
                icon: Icons.description_rounded,
                title: 'My Timecards',
                subtitle: 'Review and sign pay period timecards',
                color: palette.steel,
                onTap: () => _push(context, const TimecardsScreen()),
              ),
              if (role.canAdministerCompany)
                _MenuItem(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'PTO Allocations',
                  subtitle: 'Set per-worker vacation, sick, and personal days',
                  color: const Color(0xFF0F766E),
                  onTap: () =>
                      _push(context, const PtoAllocationsScreen()),
                ),
            ],
          ),
          const SizedBox(height: 20),

          _MenuSection(
            title: 'Account',
            items: [
              _MenuItem(
                icon: Icons.person_rounded,
                title: 'My Profile',
                subtitle: 'Name, role, language preference',
                color: palette.signal,
                onTap: () => _push(context, ProfileScreen(email: email)),
              ),
              _MenuItem(
                icon: Icons.settings_rounded,
                title: 'Settings',
                subtitle: 'Dark mode, notifications, app info',
                color: palette.steel,
                onTap: () => _push(context, const SettingsScreen()),
              ),
              _MenuItem(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                subtitle: 'Contact supervisor, report issue',
                color: palette.success,
                onTap: () => _push(context, const HelpScreen()),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Sign out
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.danger,
                side: BorderSide(color: palette.danger.withValues(alpha: 0.3)),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                ),
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text(
                      'Are you sure you want to sign out? '
                      'Unsent photos and queued events will be kept on device.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await HapticFeedback.heavyImpact();
                  await ref.read(sessionControllerProvider.notifier).signOut();
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
            ),
          ),

          const SizedBox(height: 16),

          // App version
          Center(
            child: Text(
              'FieldOps AI v1.0.0',
              style: textTheme.bodySmall?.copyWith(
                color: palette.steel.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    this.email,
    required this.palette,
    required this.textTheme,
  });

  final String? email;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final name = email?.split('@').first ?? 'Worker';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'W';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.signal,
                  palette.signal.withValues(alpha: 0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                initial,
                style: textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  email ?? 'worker@fieldops.ai',
                  style: textTheme.bodySmall?.copyWith(color: palette.steel),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.signal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(FieldOpsRadius.full),
                  ),
                  child: Text(
                    'Field Worker',
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.signal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Menu Section ─────────────────────────────────────────────

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.items});

  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.palette.steel,
              ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: item,
            )),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: title,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.steel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

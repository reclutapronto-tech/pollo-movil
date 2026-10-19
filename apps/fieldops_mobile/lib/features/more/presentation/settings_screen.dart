import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings screen — dark mode, notifications, app version.
///
/// Enhancement: shows notification status and links to system settings.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Track local toggles — in production these would persist via SharedPreferences
  bool _pushEnabled = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── Appearance ─────────────────────────────────
          _SectionHeader(title: 'Appearance', textTheme: textTheme),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceWhite,
              borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
              border: Border.all(color: palette.border, width: 0.5),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: palette.signal,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme', style: textTheme.titleMedium),
                          Text(
                            'Following system preference',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.muted,
                        borderRadius:
                            BorderRadius.circular(FieldOpsRadius.full),
                      ),
                      child: Text(
                        isDark ? 'Dark' : 'Light',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'FieldOps follows your device theme. Change it in your phone\u2019s display settings.',
                  style: textTheme.bodySmall?.copyWith(color: palette.steel),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── Notifications ──────────────────────────────
          _SectionHeader(title: 'Notifications', textTheme: textTheme),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceWhite,
              borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
              border: Border.all(color: palette.border, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_outlined, color: palette.signal),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Push Notifications', style: textTheme.titleMedium),
                      Text(
                        'Get alerts for schedule changes, OT approvals, and more.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _pushEnabled,
                  activeThumbColor: palette.signal,
                  onChanged: (value) {
                    setState(() => _pushEnabled = value);
                    // In production: toggle notification registration
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── Data & Storage ─────────────────────────────
          _SectionHeader(title: 'Data & Storage', textTheme: textTheme),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceWhite,
              borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
              border: Border.all(color: palette.border, width: 0.5),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.storage_rounded, color: palette.steel),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Offline Storage', style: textTheme.titleMedium),
                          Text(
                            'Photos, clock events, and tasks are stored locally '
                            'with encrypted SQLite and synced automatically.',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 16, color: palette.success),
                    const SizedBox(width: 6),
                    Text(
                      'Database encrypted with SQLCipher',
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ─── About ──────────────────────────────────────
          _SectionHeader(title: 'About', textTheme: textTheme),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceWhite,
              borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
              border: Border.all(color: palette.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AboutRow(label: 'App Version', value: '1.0.0'),
                const SizedBox(height: 10),
                _AboutRow(label: 'Build', value: 'Flutter ${_flutterVersion()}'),
                const SizedBox(height: 10),
                _AboutRow(label: 'Platform', value: _platformLabel()),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _flutterVersion() => '3.8.1';

  String _platformLabel() {
    final platform = Theme.of(context).platform;
    return switch (platform) {
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.android => 'Android',
      _ => platform.name,
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.textTheme});

  final String title;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: textTheme.labelMedium?.copyWith(
        color: context.palette.steel,
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: textTheme.bodyMedium),
        Text(value, style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        )),
      ],
    );
  }
}

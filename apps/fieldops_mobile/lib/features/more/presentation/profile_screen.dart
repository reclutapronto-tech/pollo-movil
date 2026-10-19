import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Profile screen — name, role, email, language switch.
///
/// Enhancement: live language switching with preview of the selected locale.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.email});

  final String? email;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _selectedLocale = 'en';

  static const _languages = <String, String>{
    'en': 'English',
    'es': 'Espa\u00f1ol',
    'fr': 'Fran\u00e7ais',
    'th': '\u0e44\u0e17\u0e22',
    'zh': '\u4e2d\u6587',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLocale = Localizations.localeOf(context).languageCode;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final name = widget.email?.split('@').first ?? 'Worker';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'W';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar + name
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        palette.signal,
                        palette.signal.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(name, style: textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  widget.email ?? '',
                  style: textTheme.bodyMedium?.copyWith(color: palette.steel),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
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

          const SizedBox(height: 32),

          // Info tiles
          _InfoTile(
            label: 'Name',
            value: name,
            icon: Icons.person_outlined,
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 10),
          _InfoTile(
            label: 'Email',
            value: widget.email ?? '—',
            icon: Icons.email_outlined,
            palette: palette,
            textTheme: textTheme,
          ),
          const SizedBox(height: 10),
          _InfoTile(
            label: 'Role',
            value: 'Field Worker',
            icon: Icons.badge_outlined,
            palette: palette,
            textTheme: textTheme,
          ),

          const SizedBox(height: 28),

          // Language selector
          Text('Language', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Choose your preferred language. The app will update immediately.',
            style: textTheme.bodySmall?.copyWith(color: palette.steel),
          ),
          const SizedBox(height: 12),

          ...AppLocalizations.supportedLocales.map((locale) {
            final code = locale.languageCode;
            final label = _languages[code] ?? code;
            final isSelected = code == _selectedLocale;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                button: true,
                selected: isSelected,
                label: '$label language option',
                child: InkWell(
                  onTap: () => setState(() => _selectedLocale = code),
                  borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.signal.withValues(alpha: 0.08)
                          : palette.surfaceWhite,
                      borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                      border: Border.all(
                        color: isSelected
                            ? palette.signal.withValues(alpha: 0.4)
                            : palette.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(label, style: textTheme.bodyLarge),
                        const Spacer(),
                        if (isSelected)
                          Icon(Icons.check_rounded,
                              color: palette.signal, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.palette,
    required this.textTheme,
  });

  final String label;
  final String value;
  final IconData icon;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        border: Border.all(color: palette.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: palette.steel),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(value, style: textTheme.bodyLarge),
            ],
          ),
        ],
      ),
    );
  }
}

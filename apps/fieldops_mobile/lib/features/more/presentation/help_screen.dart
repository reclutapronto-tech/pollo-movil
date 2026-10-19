import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Help & Support screen.
///
/// Enhancement: provides quick supervisor contact, FAQ, and feedback form.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _feedbackController = TextEditingController();
  bool _feedbackSent = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Contact supervisor
          _HelpCard(
            icon: Icons.supervisor_account_rounded,
            title: 'Contact Your Supervisor',
            subtitle: 'Call or message your supervisor directly.',
            color: palette.signal,
            palette: palette,
            textTheme: textTheme,
            trailing: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Supervisor contact will open your phone dialer once configured.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(100, 40),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // FAQ section
          Text('Common Questions', style: textTheme.titleMedium),
          const SizedBox(height: 12),

          _FAQTile(
            question: 'How do I clock in?',
            answer:
                'Go to the Jobs tab, find your assigned job, and tap "Clock In". '
                'You can also clock in from the Home tab when a job is assigned.',
            palette: palette,
            textTheme: textTheme,
          ),
          _FAQTile(
            question: 'What happens when I\u2019m offline?',
            answer:
                'All your actions (clock in/out, photos, tasks) are saved locally '
                'on your device and automatically sync when you get back online. '
                'Look for the sync status bar at the top of the screen.',
            palette: palette,
            textTheme: textTheme,
          ),
          _FAQTile(
            question: 'How do I submit an overtime request?',
            answer:
                'When you approach 8 hours, an OT prompt banner appears on Home. '
                'Tap "Submit OT Request" or go to the job detail and tap "Request Overtime".',
            palette: palette,
            textTheme: textTheme,
          ),
          _FAQTile(
            question: 'Where are my saved photos?',
            answer:
                'Photos saved for later are stored on your device. '
                'Open the job and tap "Saved Photos" to view and send them.',
            palette: palette,
            textTheme: textTheme,
          ),

          const SizedBox(height: 24),

          // Feedback form
          Text('Send Feedback', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Found a bug or have a suggestion? Let us know.',
            style: textTheme.bodySmall?.copyWith(color: palette.steel),
          ),
          const SizedBox(height: 12),

          if (_feedbackSent)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                border: Border.all(
                  color: palette.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: palette.success, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Thank you for your feedback! We\u2019ll review it soon.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.success,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _feedbackController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Describe the issue or suggestion...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _feedbackController.text.trim().isEmpty
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _feedbackSent = true;
                          _feedbackController.clear();
                        });
                      },
                child: const Text('Submit Feedback'),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.palette,
    required this.textTheme,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final FieldOpsPalette palette;
  final TextTheme textTheme;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
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
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _FAQTile extends StatefulWidget {
  const _FAQTile({
    required this.question,
    required this.answer,
    required this.palette,
    required this.textTheme,
  });

  final String question;
  final String answer;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  State<_FAQTile> createState() => _FAQTileState();
}

class _FAQTileState extends State<_FAQTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: widget.palette.surfaceWhite,
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
          border: Border.all(color: widget.palette.border, width: 0.5),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: widget.textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: widget.palette.steel,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  widget.answer,
                  style: widget.textTheme.bodyMedium?.copyWith(
                    color: widget.palette.slate,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

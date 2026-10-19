import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/presentation/foreman_schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForemanScheduleScreen extends ConsumerWidget {
  const ForemanScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(foremanScheduleControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crew Schedule'),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy_rounded),
            tooltip: 'Copy last week into this week',
            onPressed: () => _onCopyLastWeek(context, ref),
          ),
        ],
      ),
      body: controllerState.when(
        data: (scheduleState) {
          if (scheduleState.shifts.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref
                  .read(foremanScheduleControllerProvider.notifier)
                  .reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: const [
                  SizedBox(height: 140),
                  _CrewEmptyState(),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Pending approval banner
              _ApprovalBanner(palette: palette),

              // Shift list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref
                      .read(foremanScheduleControllerProvider.notifier)
                      .reload(),
                  child: _CrewShiftList(
                    shifts: scheduleState.shifts,
                    palette: palette,
                    textTheme: textTheme,
                  ),
                ),
              ),

              // Save button
              if (scheduleState.hasUnsavedChanges)
                _SaveBar(
                  isSaving: scheduleState.isSaving,
                  palette: palette,
                ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonLoader(itemCount: 5),
        ),
        error: (error, _) {
          final repositoryError = error is ScheduleRepositoryException
              ? error
              : const ScheduleRepositoryException.unknown();
          return RefreshIndicator(
            onRefresh: () => ref
                .read(foremanScheduleControllerProvider.notifier)
                .reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 140),
                _CrewErrorState(message: repositoryError.message),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onCopyLastWeek(BuildContext context, WidgetRef ref) async {
    // Week anchor = Monday of the current week (local clock).
    final now = DateTime.now();
    final thisMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: (now.weekday - DateTime.monday) % 7));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final lastSunday = thisMonday.subtract(const Duration(days: 1));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Copy last week?'),
        content: Text(
          'Copy every shift from ${_fmt(lastMonday)}–${_fmt(lastSunday)} into '
          'the week of ${_fmt(thisMonday)} as drafts. Publish them from the '
          'web schedule once you have reviewed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final copied = await ref.read(scheduleRepositoryProvider).copyWeek(
            sourceStart: lastMonday,
            sourceEnd: lastSunday,
            targetStart: thisMonday,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            copied == 0
                ? 'Last week had no shifts to copy.'
                : 'Copied $copied shift${copied == 1 ? '' : 's'} as drafts.',
          ),
        ),
      );
      if (copied > 0) {
        await ref
            .read(foremanScheduleControllerProvider.notifier)
            .reload();
      }
    } on ScheduleRepositoryException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─── Approval Banner ──────────────────────────────────────────

class _ApprovalBanner extends StatelessWidget {
  const _ApprovalBanner({required this.palette});

  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.signal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FieldOpsRadius.md),
        border: Border.all(
          color: palette.signal.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_top_rounded,
            size: 18,
            color: palette.signal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pending supervisor approval',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.signal,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Crew Shift List (Reorderable) ────────────────────────────

class _CrewShiftList extends ConsumerWidget {
  const _CrewShiftList({
    required this.shifts,
    required this.palette,
    required this.textTheme,
  });

  final List<CrewScheduleShift> shifts;
  final FieldOpsPalette palette;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group shifts by date for section headers.
    final grouped = <String, List<_IndexedShift>>{};
    for (var i = 0; i < shifts.length; i++) {
      final label = _dateLabel(shifts[i].shiftDate);
      grouped.putIfAbsent(label, () => []);
      grouped[label]!.add(_IndexedShift(index: i, shift: shifts[i]));
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      physics: const AlwaysScrollableScrollPhysics(),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
            color: Colors.transparent,
            child: child,
          ),
          child: child,
        );
      },
      itemCount: shifts.length,
      itemBuilder: (context, index) {
        final shift = shifts[index];
        // Show a date header before the first shift of each day.
        final showHeader = index == 0 ||
            _dateKey(shifts[index].shiftDate) !=
                _dateKey(shifts[index - 1].shiftDate);

        return Padding(
          key: ValueKey(shift.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 8),
                  child: Text(
                    _dateLabel(shift.shiftDate),
                    style: textTheme.headlineMedium,
                  ),
                ),
              _CrewShiftTile(shift: shift, palette: palette),
            ],
          ),
        );
      },
      onReorderItem: (oldIndex, newIndex) {
        HapticFeedback.mediumImpact();
        ref
            .read(foremanScheduleControllerProvider.notifier)
            .reorder(oldIndex, newIndex);
      },
    );
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  String _dateLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final shiftDay = DateTime(value.year, value.month, value.day);
    final diff = shiftDay.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
  }
}

class _IndexedShift {
  const _IndexedShift({required this.index, required this.shift});
  final int index;
  final CrewScheduleShift shift;
}

// ─── Shift Tile ───────────────────────────────────────────────

class _CrewShiftTile extends StatelessWidget {
  const _CrewShiftTile({required this.shift, required this.palette});

  final CrewScheduleShift shift;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Drag handle
            Icon(
              Icons.drag_indicator_rounded,
              color: palette.steel.withValues(alpha: 0.4),
              size: 22,
            ),
            const SizedBox(width: 12),

            // Shift info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shift.workerName, style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(shift.jobName, style: textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: palette.steel,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${shift.startTime} - ${shift.endTime}',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Status badge
            _StatusBadge(status: shift.status, palette: palette),
          ],
        ),
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.palette});

  final String status;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'published' => ('Published', palette.success),
      'draft' => ('Draft', palette.steel),
      'pending_approval' => ('Pending', palette.signal),
      _ => (status, palette.steel),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FieldOpsRadius.full),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

// ─── Save Bar ─────────────────────────────────────────────────

class _SaveBar extends ConsumerWidget {
  const _SaveBar({required this.isSaving, required this.palette});

  final bool isSaving;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        border: Border(
          top: BorderSide(color: palette.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isSaving
                ? null
                : () async {
                    await HapticFeedback.mediumImpact();
                    final success = await ref
                        .read(foremanScheduleControllerProvider.notifier)
                        .saveChanges();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Schedule changes saved'
                                : 'Failed to save changes',
                          ),
                        ),
                      );
                    }
                  },
            child: isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Changes'),
          ),
        ),
      ),
    );
  }
}

// ─── Empty / Error States ─────────────────────────────────────

class _CrewEmptyState extends StatelessWidget {
  const _CrewEmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.groups_rounded,
          size: 48,
          color: Colors.black.withValues(alpha: 0.32),
        ),
        const SizedBox(height: 12),
        Text(
          'No crew shifts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Crew shifts will appear here once published.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CrewErrorState extends StatelessWidget {
  const _CrewErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 48,
          color: Colors.black.withValues(alpha: 0.32),
        ),
        const SizedBox(height: 12),
        Text(
          'Schedule unavailable',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

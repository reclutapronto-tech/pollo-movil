import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/presentation/widgets/schedule_calendar.dart';
import 'package:fieldops_mobile/features/schedule/presentation/worker_schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _CalendarView { month, week }

class WorkerScheduleScreen extends ConsumerStatefulWidget {
  const WorkerScheduleScreen({super.key});

  @override
  ConsumerState<WorkerScheduleScreen> createState() =>
      _WorkerScheduleScreenState();
}

class _WorkerScheduleScreenState extends ConsumerState<WorkerScheduleScreen> {
  _CalendarView _view = _CalendarView.month;
  late DateTime _displayMonth;
  late DateTime _selectedDay;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  DateTime get _weekStart {
    final d = _selectedDay;
    return d.subtract(Duration(days: d.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheduleState = ref.watch(workerScheduleControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mySchedule),
        leading: const BackButton(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<_CalendarView>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              segments: const [
                ButtonSegment(
                  value: _CalendarView.month,
                  icon: Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text('Month'),
                ),
                ButtonSegment(
                  value: _CalendarView.week,
                  icon: Icon(Icons.view_week_rounded, size: 18),
                  label: Text('Week'),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
        ],
      ),
      body: scheduleState.when(
        data: (shifts) {
          if (shifts.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: const [SizedBox(height: 140), _ScheduleEmptyState()],
            );
          }
          final shiftDates = shifts
              .map((s) => DateTime(s.shiftDate.year, s.shiftDate.month, s.shiftDate.day))
              .toSet();

          return _view == _CalendarView.week
              ? _buildWeekView(shifts, shiftDates, palette, textTheme)
              : _buildMonthView(shifts, shiftDates, palette, textTheme, l10n);
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonLoader(itemCount: 4),
        ),
        error: (error, _) {
          final msg = error is ScheduleRepositoryException
              ? error
              : const ScheduleRepositoryException.unknown();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [const SizedBox(height: 140), _ScheduleErrorState(message: msg.message)],
          );
        },
      ),
    );
  }

  // ─── Month view ───────────────────────────────────────────────

  Widget _buildMonthView(
    List<WorkerScheduleShift> shifts,
    Set<DateTime> shiftDates,
    FieldOpsPalette palette,
    TextTheme textTheme,
    AppLocalizations l10n,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(workerScheduleControllerProvider.notifier).reload(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: palette.surfaceWhite,
                  borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    // Month navigation
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(() {
                            _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
                          }),
                          icon: const Icon(Icons.chevron_left_rounded),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Text(
                            '${_monthNames[_displayMonth.month - 1]} ${_displayMonth.year}',
                            textAlign: TextAlign.center,
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1);
                          }),
                          icon: const Icon(Icons.chevron_right_rounded),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ScheduleCalendar(
                      month: _displayMonth.month,
                      year: _displayMonth.year,
                      shiftDates: shiftDates,
                      selectedDate: _selectedDay,
                      onDateSelected: (date) => setState(() {
                        _selectedDay = _selectedDay == date ? _selectedDay : date;
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.upcomingShifts, style: textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(l10n.scheduleHelp, style: textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverReorderableList(
              itemCount: shifts.length,
              itemBuilder: (context, index) {
                final shift = shifts[index];
                return Padding(
                  key: ValueKey(shift.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ScheduleCard(shift: shift, palette: palette),
                );
              },
              onReorderItem: (oldIndex, newIndex) {
                ref.read(workerScheduleControllerProvider.notifier).reorderShifts(oldIndex, newIndex);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Week / Gantt view ────────────────────────────────────────

  Widget _buildWeekView(
    List<WorkerScheduleShift> shifts,
    Set<DateTime> shiftDates,
    FieldOpsPalette palette,
    TextTheme textTheme,
  ) {
    final weekStart = _weekStart;
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    final dayShifts = shifts.where((s) {
      final d = DateTime(s.shiftDate.year, s.shiftDate.month, s.shiftDate.day);
      return d == _selectedDay;
    }).toList();

    return Column(
      children: [
        // Week day picker
        Container(
          color: palette.surfaceWhite,
          child: Column(
            children: [
              // Week navigation row
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() =>
                        _selectedDay = _selectedDay.subtract(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_left_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${_monthNames[weekStart.month - 1]} ${weekStart.year}',
                      textAlign: TextAlign.center,
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() =>
                        _selectedDay = _selectedDay.add(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_right_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              // Day buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: days.map((day) {
                    final isSelected = day == _selectedDay;
                    final isToday = day == todayNorm;
                    final hasShift = shiftDates.contains(day);

                    return GestureDetector(
                      onTap: () => setState(() => _selectedDay = day),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dayInitials[day.weekday - 1],
                            style: textTheme.labelSmall?.copyWith(
                              color: isSelected ? palette.signal : palette.steel,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? palette.signal
                                  : hasShift
                                      ? palette.signal.withValues(alpha: 0.1)
                                      : null,
                              border: isToday && !isSelected
                                  ? Border.all(color: palette.signal, width: 1.5)
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${day.day}',
                              style: textTheme.bodySmall?.copyWith(
                                color: isSelected
                                    ? Colors.white
                                    : (isToday || hasShift)
                                        ? palette.signal
                                        : palette.slate,
                                fontWeight: isSelected || isToday || hasShift
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: hasShift ? palette.signal : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              Divider(height: 1, color: palette.border),
            ],
          ),
        ),

        // Shifts for selected day
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(workerScheduleControllerProvider.notifier).reload(),
            child: dayShifts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      const SizedBox(height: 60),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.event_available_rounded, size: 40,
                                color: palette.steel.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('No shifts this day', style: textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    itemCount: dayShifts.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ScheduleCard(shift: dayShifts[i], palette: palette),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.shift, required this.palette});

  final WorkerScheduleShift shift;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dateLabel = _formatDate(shift.shiftDate);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shift.jobName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (shift.isRecentlyUpdated)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.signal.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.updated,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.signal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ScheduleChip(
                  icon: Icons.calendar_today_rounded,
                  label: dateLabel,
                ),
                _ScheduleChip(
                  icon: Icons.schedule_rounded,
                  label: '${shift.startTime} - ${shift.endTime}',
                ),
              ],
            ),
            if ((shift.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                shift.notes!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: 'Request shift swap for ${shift.jobName} on $dateLabel',
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.steel,
                    side: BorderSide(
                      color: palette.steel.withValues(alpha: 0.25),
                    ),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: () async {
                    final confirmed = await _SwapConfirmDialog.show(
                      context,
                      jobName: shift.jobName,
                      dateLabel: dateLabel,
                    );
                    if (confirmed != true || !context.mounted) return;

                    await HapticFeedback.mediumImpact();
                    try {
                      await ref
                          .read(scheduleRepositoryProvider)
                          .requestShiftSwap(shiftId: shift.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Swap request submitted'),
                          ),
                        );
                      }
                    } on ScheduleRepositoryException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.message)),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Request Swap'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
  }
}

class _ScheduleChip extends StatelessWidget {
  const _ScheduleChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _SwapConfirmDialog extends StatelessWidget {
  const _SwapConfirmDialog({required this.jobName, required this.dateLabel});

  final String jobName;
  final String dateLabel;

  static Future<bool?> show(
    BuildContext context, {
    required String jobName,
    required String dateLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) =>
          _SwapConfirmDialog(jobName: jobName, dateLabel: dateLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Request Shift Swap'),
      content: Text(
        'Submit a swap request for $jobName on $dateLabel? '
        'Your supervisor will be notified.',
        style: textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Request Swap'),
        ),
      ],
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Icon(Icons.event_busy_rounded, size: 48, color: Colors.black.withValues(alpha: 0.32)),
        const SizedBox(height: 12),
        Text(l10n.noScheduledShiftsYet, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l10n.scheduleWillAppear,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ScheduleErrorState extends StatelessWidget {
  const _ScheduleErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black.withValues(alpha: 0.32)),
        const SizedBox(height: 12),
        Text(l10n.scheduleUnavailable, style: Theme.of(context).textTheme.titleLarge),
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

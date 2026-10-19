import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Compact month calendar showing shift dates highlighted.
///
/// Selecting a day with shifts scrolls/filters to that day.
class ScheduleCalendar extends StatelessWidget {
  const ScheduleCalendar({
    super.key,
    required this.month,
    required this.year,
    required this.shiftDates,
    this.selectedDate,
    this.onDateSelected,
  });

  final int month;
  final int year;
  final Set<DateTime> shiftDates;
  final DateTime? selectedDate;
  final void Function(DateTime date)? onDateSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final firstOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startingWeekday = firstOfMonth.weekday; // Mon=1 ... Sun=7

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Day labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: dayLabels
              .map((d) => SizedBox(
                    width: 36,
                    child: Center(
                      child: Text(
                        d,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.steel,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),

        // Days grid — only render rows that contain at least one real day
        ...List.generate(6, (weekRow) {
          // Check if any cell in this row falls within the month.
          final firstCellDay = weekRow * 7 + 1 - (startingWeekday - 1);
          final lastCellDay = firstCellDay + 6;
          if (lastCellDay < 1 || firstCellDay > daysInMonth) {
            return const SizedBox.shrink(); // skip empty trailing weeks
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (col) {
                final dayIndex = weekRow * 7 + col + 1 - (startingWeekday - 1);
                if (dayIndex < 1 || dayIndex > daysInMonth) {
                  return const SizedBox(width: 36, height: 36);
                }

                final date = DateTime(year, month, dayIndex);
                final hasShift = shiftDates.contains(date);
                final isToday = date == todayDate;
                final isSelected = selectedDate != null &&
                    date.year == selectedDate!.year &&
                    date.month == selectedDate!.month &&
                    date.day == selectedDate!.day;

                return GestureDetector(
                  onTap: () => onDateSelected?.call(date),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.signal
                          : hasShift
                              ? palette.signal.withValues(alpha: 0.12)
                              : null,
                      border: isToday
                          ? Border.all(color: palette.signal, width: 1.5)
                          : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$dayIndex',
                      style: textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? Colors.white
                            : hasShift
                                ? palette.signal
                                : palette.slate,
                        fontWeight: hasShift || isToday
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }
}

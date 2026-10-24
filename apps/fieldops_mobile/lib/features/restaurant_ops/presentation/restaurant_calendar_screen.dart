import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantCalendarScreen extends ConsumerStatefulWidget {
  const RestaurantCalendarScreen({
    super.key,
    required this.branchId,
    required this.initialDate,
    required this.canManage,
    this.highlightTaskId,
  });

  final String branchId;
  final String initialDate;
  final bool canManage;
  final String? highlightTaskId;

  @override
  ConsumerState<RestaurantCalendarScreen> createState() =>
      _RestaurantCalendarScreenState();
}

class _RestaurantCalendarScreenState
    extends ConsumerState<RestaurantCalendarScreen> {
  late DateTime _weekStart;
  late Future<OpsJson> _request;
  String? _savingDate;
  bool _schedulingWeek = false;
  String? _savingTaskId;
  String? _savingPartId;
  String? _reschedulingTaskId;
  String? _assigningDate;

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(widget.initialDate);
    _request = _fetch();
  }

  String get _fromDate => _dateString(_weekStart);
  String get _toDate => _dateString(_weekStart.add(const Duration(days: 6)));

  Future<OpsJson> _fetch() => ref
      .read(restaurantOpsRepositoryProvider)
      .fetchTaskCalendar(widget.branchId, fromDate: _fromDate, toDate: _toDate);

  void _moveWeek(int count) {
    if (_reschedulingTaskId != null) return;
    setState(() {
      _weekStart = _weekStart.add(Duration(days: count * 7));
      _request = _fetch();
    });
  }

  Future<void> _refresh() async {
    final request = _fetch();
    setState(() => _request = request);
    try {
      await request;
    } on Object {
      // FutureBuilder renders the existing request error state.
    }
  }

  Future<void> _schedule(String date, {required String today}) async {
    if (_savingDate != null ||
        _schedulingWeek ||
        _assigningDate != null ||
        _savingTaskId != null ||
        _savingPartId != null ||
        _reschedulingTaskId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (date.compareTo(today) < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantCalendarRetroactive)),
      );
      return;
    }
    setState(() => _savingDate = date);
    try {
      final result = await ref
          .read(restaurantOpsRepositoryProvider)
          .scheduleTasks(widget.branchId, date);
      if (!mounted) return;
      final count = (result['created_count'] as num? ?? 0).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantCalendarDayScheduled(count))),
      );
      await _refresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingDate = null);
    }
  }

  Future<void> _scheduleWeek({required String today}) async {
    if (_schedulingWeek ||
        _savingDate != null ||
        _assigningDate != null ||
        _savingTaskId != null ||
        _savingPartId != null ||
        _reschedulingTaskId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final dates = List.generate(
      7,
      (index) => _dateString(_weekStart.add(Duration(days: index))),
    ).where((date) => date.compareTo(today) >= 0).toList();
    if (dates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.restaurantCalendarPastWeek)));
      return;
    }

    setState(() => _schedulingWeek = true);
    var createdCount = 0;
    final failedDates = <String>[];
    try {
      for (final date in dates) {
        try {
          final result = await ref
              .read(restaurantOpsRepositoryProvider)
              .scheduleTasks(widget.branchId, date);
          createdCount += (result['created_count'] as num? ?? 0).toInt();
        } on Object {
          failedDates.add(date);
        }
      }
      if (!mounted) return;
      final pastDays = 7 - dates.length;
      final scheduledDays = dates.length - failedDates.length;
      final message = failedDates.isEmpty
          ? l10n.restaurantCalendarWeekScheduled(
              createdCount,
              scheduledDays,
              pastDays,
            )
          : l10n.restaurantCalendarWeekPartial(
              createdCount,
              scheduledDays,
              failedDates.join(', '),
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _schedulingWeek = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> task, String? employeeId) async {
    if (_savingTaskId != null ||
        _savingPartId != null ||
        _schedulingWeek ||
        _savingDate != null ||
        _assigningDate != null ||
        _reschedulingTaskId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final taskId = task['id'] as String?;
    if (taskId == null) return;
    setState(() => _savingTaskId = taskId);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .assignTask(widget.branchId, taskId, employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantCalendarTaskAssigneeUpdated)),
      );
      await _refresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _savingTaskId = null);
    }
  }

  Future<void> _assignPart(
    Map<String, dynamic> task,
    Map<String, dynamic> part,
    String? employeeId,
  ) async {
    if (_savingTaskId != null ||
        _savingPartId != null ||
        _schedulingWeek ||
        _savingDate != null ||
        _assigningDate != null ||
        _reschedulingTaskId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final taskId = task['id'] as String?;
    final partId = part['id'] as String?;
    if (taskId == null || partId == null) return;
    setState(() => _savingPartId = partId);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .assignTaskPart(widget.branchId, taskId, partId, employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantCalendarPartAssigneeUpdated)),
      );
      await _refresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _savingPartId = null);
    }
  }

  Future<void> _autoAssignDate(String date) async {
    if (_assigningDate != null ||
        _schedulingWeek ||
        _savingDate != null ||
        _savingTaskId != null ||
        _savingPartId != null ||
        _reschedulingTaskId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _assigningDate = date);
    try {
      final result = await ref
          .read(restaurantOpsRepositoryProvider)
          .autoAssignTasks(widget.branchId, forDate: date);
      if (!mounted) return;
      final assigned = (result['assigned_count'] as num? ?? 0).toInt();
      final unassigned = (result['unassigned_count'] as num? ?? 0).toInt();
      final planner = result['planner'] == 'timefold'
          ? 'Timefold'
          : l10n.restaurantCalendarLocalPlanner;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.restaurantCalendarAutoAssignResult(
              assigned,
              planner,
              unassigned,
            ),
          ),
        ),
      );
      await _refresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _assigningDate = null);
    }
  }

  Future<void> _rescheduleTask(
    Map<String, dynamic> task, {
    required String today,
    required bool offlineSnapshot,
  }) async {
    if (!widget.canManage ||
        offlineSnapshot ||
        _savingDate != null ||
        _schedulingWeek ||
        _assigningDate != null ||
        _savingTaskId != null ||
        _savingPartId != null ||
        _reschedulingTaskId != null) {
      return;
    }

    final taskId = task['id'] as String?;
    final scheduledFor = task['scheduled_for'] as String?;
    final parts = (task['parts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final todayDate = DateTime.tryParse('${today}T00:00:00');
    final currentDate = scheduledFor == null
        ? null
        : DateTime.tryParse('${scheduledFor}T00:00:00');
    if (taskId == null ||
        todayDate == null ||
        currentDate == null ||
        task['status'] != 'pending' ||
        task['task_source'] != 'scheduled' ||
        task['activity_template_id'] is! String ||
        task['configuration_pending'] == true ||
        (task['assigned_to'] as String? ?? '').isNotEmpty ||
        parts.any((part) => (part['assigned_to'] as String? ?? '').isNotEmpty)) {
      return;
    }

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentDate.isBefore(todayDate) ? todayDate : currentDate,
      firstDate: todayDate,
      lastDate: DateTime(9999, 12, 31),
      helpText: MaterialLocalizations.of(context).datePickerHelpText,
    );
    if (!mounted || selectedDate == null) return;

    final nextDate = _dateString(selectedDate);
    if (nextDate == scheduledFor) return;

    setState(() => _reschedulingTaskId = taskId);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .rescheduleTask(widget.branchId, taskId, nextDate);
      if (!mounted) return;
      final formattedDate = MaterialLocalizations.of(
        context,
      ).formatMediumDate(selectedDate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context)!.restaurantOpsSaved} $formattedDate',
          ),
        ),
      );
      await _refresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _reschedulingTaskId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      previous,
      next,
    ) {
      if (next.hasValue && mounted) {
        final request = _fetch();
        setState(() => _request = request);
      }
    });
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.restaurantCalendarTitle),
        actions: [
          IconButton(
            tooltip: l10n.restaurantCalendarRefresh,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<OpsJson>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.restaurantCalendarLoadError),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l10n.restaurantCalendarRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          final tasks = (snapshot.data?['tasks'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final assignableMembers =
              (snapshot.data?['assignable_members'] as List<dynamic>? ??
                      const [])
                  .whereType<Map<String, dynamic>>()
                  .toList(growable: false);
          final unassignedCount = tasks.fold<int>(0, (count, task) {
            if (task['configuration_pending'] == true) return count;
            final parts = (task['parts'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>();
            if (parts.isNotEmpty) {
              if (task['status'] != 'pending' &&
                  task['status'] != 'in_progress') {
                return count;
              }
              return count +
                  parts
                      .where(
                        (part) =>
                            part['status'] == 'pending' &&
                            (part['assigned_to'] == null ||
                                part['assigned_to'] == ''),
                      )
                      .length;
            }
            return count +
                (task['status'] == 'pending' &&
                        (task['assigned_to'] == null ||
                            task['assigned_to'] == '')
                    ? 1
                    : 0);
          });
          final completedCount = tasks
              .where((task) => task['status'] == 'completed')
              .length;
          final offlineSnapshot =
              snapshot.hasError || snapshot.data?['_offline_snapshot'] == true;
          final today = offlineSnapshot
              ? widget.initialDate
              : (snapshot.data?['local_date'] as String? ?? widget.initialDate);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: l10n.restaurantCalendarPreviousWeek,
                      onPressed: _schedulingWeek ||
                              _savingDate != null ||
                              _reschedulingTaskId != null
                          ? null
                          : () => _moveWeek(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${MaterialLocalizations.of(context).formatShortDate(_weekStart)} – ${MaterialLocalizations.of(context).formatShortDate(_weekStart.add(const Duration(days: 6)))}',
                            style: Theme.of(context).textTheme.titleSmall,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            widget.canManage
                                ? l10n.restaurantCalendarManagerHint
                                : l10n.restaurantCalendarBranchHint,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: l10n.restaurantCalendarNextWeek,
                      onPressed: _schedulingWeek ||
                              _savingDate != null ||
                              _reschedulingTaskId != null
                          ? null
                          : () => _moveWeek(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              if (offlineSnapshot)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.restaurantCalendarOffline),
                  ),
                ),
              if (widget.canManage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            !offlineSnapshot &&
                                _savingDate == null &&
                                !_schedulingWeek &&
                                _assigningDate == null &&
                                _savingTaskId == null &&
                                _savingPartId == null &&
                                _reschedulingTaskId == null
                            ? () => _scheduleWeek(today: today)
                            : null,
                        icon: _schedulingWeek
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.date_range_rounded),
                        label: Text(
                          _schedulingWeek
                              ? l10n.restaurantCalendarPlanningWeek
                              : l10n.restaurantCalendarPlanWeek,
                        ),
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.calendar_month_rounded,
                          size: 18,
                        ),
                        label: Text(
                          l10n.restaurantCalendarWeekActivities(tasks.length),
                        ),
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.assignment_late_outlined,
                          size: 18,
                        ),
                        label: Text(
                          l10n.restaurantCalendarUnassignedCount(
                            unassignedCount,
                          ),
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.task_alt_rounded, size: 18),
                        label: Text(
                          l10n.restaurantCalendarCompletedCount(completedCount),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: 7,
                    itemBuilder: (context, index) {
                      final day = _weekStart.add(Duration(days: index));
                      final date = _dateString(day);
                      final dayTasks = tasks
                          .where((task) => task['scheduled_for'] == date)
                          .toList(growable: false);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      MaterialLocalizations.of(
                                        context,
                                      ).formatFullDate(day),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ),
                                  Text(
                                    l10n.restaurantCalendarActivityCount(
                                      dayTasks.length,
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.canManage) ...[
                                const SizedBox(height: 8),
                                if (date.compareTo(today) < 0)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      l10n.restaurantCalendarPastDate,
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed:
                                        !offlineSnapshot &&
                                            date.compareTo(today) >= 0 &&
                                            _savingDate == null &&
                                            !_schedulingWeek &&
                                            _assigningDate == null &&
                                            _savingTaskId == null &&
                                            _savingPartId == null &&
                                            _reschedulingTaskId == null
                                        ? () => _schedule(date, today: today)
                                        : null,
                                    icon: _savingDate == date
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.event_available_rounded,
                                          ),
                                    label: Text(
                                      _savingDate == date
                                          ? l10n.restaurantCalendarScheduling
                                          : l10n.restaurantCalendarScheduleFromRules,
                                    ),
                                  ),
                                ),
                              ],
                              if (widget.canManage && date.compareTo(today) >= 0)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed:
                                        offlineSnapshot ||
                                            _assigningDate != null ||
                                            _schedulingWeek ||
                                            _savingDate != null ||
                                            _savingTaskId != null ||
                                            _savingPartId != null ||
                                            _reschedulingTaskId != null
                                        ? null
                                        : () => _autoAssignDate(date),
                                    icon: _assigningDate == date
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.assignment_turned_in_outlined,
                                          ),
                                    label: Text(
                                      _assigningDate == date
                                          ? l10n.restaurantCalendarAssigning
                                          : l10n.restaurantCalendarAssignEligible,
                                    ),
                                  ),
                                ),
                              if (dayTasks.isEmpty)
                                Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text(
                                    l10n.restaurantCalendarNoActivities,
                                  ),
                                )
                              else
                                ...dayTasks.map((task) {
                                  final taskId = task['id'] as String?;
                                  final assignedTo =
                                      task['assigned_to'] as String? ?? '';
                                  final canAssign =
                                      widget.canManage &&
                                      task['status'] == 'pending' &&
                                      task['configuration_pending'] != true &&
                                      task['is_divisible'] != true;
                                  final parts =
                                      (task['parts'] as List<dynamic>? ??
                                              const [])
                                          .whereType<Map<String, dynamic>>()
                                          .toList(growable: false);
                                  final canReschedule =
                                      widget.canManage &&
                                      !offlineSnapshot &&
                                      task['status'] == 'pending' &&
                                      task['task_source'] == 'scheduled' &&
                                      task['activity_template_id'] is String &&
                                      task['configuration_pending'] != true &&
                                      assignedTo.isEmpty &&
                                      parts.every(
                                        (part) =>
                                            (part['assigned_to'] as String? ?? '')
                                                .isEmpty,
                                      );
                                  final isHighlighted =
                                      widget.highlightTaskId != null &&
                                      (taskId == widget.highlightTaskId ||
                                          parts.any(
                                            (part) =>
                                                part['id'] ==
                                                widget.highlightTaskId,
                                          ));
                                  final currentAssigneeMissing =
                                      assignedTo.isNotEmpty &&
                                      !assignableMembers.any(
                                        (member) => member['id'] == assignedTo,
                                      );
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Column(
                                      children: [
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          selected: isHighlighted,
                                          selectedTileColor: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          title: Text(
                                            task['name'] as String? ??
                                                l10n.restaurantCalendarFallbackActivity,
                                          ),
                                          subtitle: Text(
                                            [
                                              if (task['area_name'] is String)
                                                task['area_name'],
                                              if (task['assignee_name']
                                                  is String)
                                                task['assignee_name']
                                              else
                                                l10n.restaurantCalendarNoAssignee,
                                              if (task['estimated_minutes']
                                                  is num)
                                                '${task['estimated_minutes']} min',
                                            ].join(' · '),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (canReschedule)
                                                IconButton(
                                                  tooltip:
                                                      MaterialLocalizations.of(
                                                        context,
                                                      ).datePickerHelpText,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed:
                                                      _reschedulingTaskId ==
                                                              null &&
                                                          _savingTaskId == null &&
                                                          _savingPartId == null &&
                                                          _savingDate == null &&
                                                          !_schedulingWeek &&
                                                          _assigningDate == null
                                                      ? () => _rescheduleTask(
                                                          task,
                                                          today: today,
                                                          offlineSnapshot:
                                                              offlineSnapshot,
                                                        )
                                                      : null,
                                                  icon:
                                                      _reschedulingTaskId ==
                                                              taskId
                                                          ? const SizedBox(
                                                              width: 18,
                                                              height: 18,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                            )
                                                          : const Icon(
                                                              Icons.edit_calendar_outlined,
                                                            ),
                                                ),
                                              Text(
                                                _status(
                                                  task['status'] as String? ??
                                                      'pending',
                                                  l10n,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (task['configuration_pending'] ==
                                            true)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Text(
                                                l10n.restaurantCalendarConfigurationPending,
                                              ),
                                            ),
                                          ),
                                        if (canAssign)
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: SizedBox(
                                              width: 220,
                                              child: DropdownButtonFormField<String?>(
                                                isExpanded: true,
                                                value: assignedTo,
                                                decoration: InputDecoration(
                                                  labelText: l10n
                                                      .restaurantCalendarAssignee,
                                                  isDense: true,
                                                ),
                                                items: [
                                                  DropdownMenuItem(
                                                    value: '',
                                                    child: Text(
                                                      l10n.restaurantCalendarNoAssignee,
                                                    ),
                                                  ),
                                                  if (currentAssigneeMissing)
                                                    DropdownMenuItem(
                                                      value: assignedTo,
                                                      enabled: false,
                                                      child: Text(
                                                        l10n.restaurantCalendarInactiveAssignee(
                                                          task['assignee_name']
                                                                  as String? ??
                                                              l10n.restaurantCalendarFallbackAssignee,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ...assignableMembers.map(
                                                    (
                                                      member,
                                                    ) => DropdownMenuItem(
                                                      value:
                                                          member['id']
                                                              as String?,
                                                      child: Text(
                                                        member['full_name']
                                                                as String? ??
                                                            member['id']
                                                                as String? ??
                                                            l10n.restaurantCalendarEmployeeFallback,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                onChanged:
                                                    !offlineSnapshot &&
                                                        _savingTaskId == null &&
                                                        _savingPartId == null &&
                                                        _assigningDate == null &&
                                                        _reschedulingTaskId == null
                                                    ? (value) => _assign(
                                                        task,
                                                        value?.isEmpty == true
                                                            ? null
                                                            : value,
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        if (parts.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Column(
                                              children: [
                                                const Divider(),
                                                for (final part in parts)
                                                  Column(
                                                    children: [
                                                      ListTile(
                                                        dense: true,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        title: Text(
                                                          part['zone_name']
                                                                  as String? ??
                                                              l10n.restaurantCalendarZoneFallback,
                                                        ),
                                                        subtitle: Text(
                                                          [
                                                            part['assignee_name']
                                                                    as String? ??
                                                                l10n.restaurantCalendarNoAssignee,
                                                            if (part['estimated_minutes']
                                                                is num)
                                                              '${part['estimated_minutes']} min',
                                                            _status(
                                                              part['status']
                                                                      as String? ??
                                                                  'pending',
                                                              l10n,
                                                            ),
                                                          ].join(' · '),
                                                        ),
                                                      ),
                                                      if (widget.canManage &&
                                                          task['configuration_pending'] !=
                                                              true &&
                                                          (task['status'] ==
                                                                  'pending' ||
                                                              task['status'] ==
                                                                  'in_progress') &&
                                                          part['status'] ==
                                                              'pending')
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 8,
                                                              ),
                                                          child: DropdownButtonFormField<String>(
                                                            isExpanded: true,
                                                            value:
                                                                part['assigned_to']
                                                                    as String? ??
                                                                '',
                                                            decoration: InputDecoration(
                                                              labelText: l10n.restaurantCalendarZoneAssignee(
                                                                part['zone_name']
                                                                        as String? ??
                                                                    l10n.restaurantCalendarZoneFallback,
                                                              ),
                                                              isDense: true,
                                                            ),
                                                            items: [
                                                              DropdownMenuItem(
                                                                value: '',
                                                                child: Text(
                                                                  l10n.restaurantCalendarNoAssignee,
                                                                ),
                                                              ),
                                                              if (part['assigned_to']
                                                                      is String &&
                                                                  !assignableMembers.any(
                                                                    (member) =>
                                                                        member['id'] ==
                                                                        part['assigned_to'],
                                                                  ))
                                                                DropdownMenuItem(
                                                                  value:
                                                                      part['assigned_to']
                                                                          as String,
                                                                  enabled:
                                                                      false,
                                                                  child: Text(
                                                                    l10n.restaurantCalendarInactiveAssignee(
                                                                      part['assignee_name']
                                                                              as String? ??
                                                                          l10n.restaurantCalendarFallbackAssignee,
                                                                    ),
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              ...assignableMembers.map(
                                                                (
                                                                  member,
                                                                ) => DropdownMenuItem<String>(
                                                                  value:
                                                                      member['id']
                                                                          as String? ??
                                                                      '',
                                                                  child: Text(
                                                                    member['full_name']
                                                                            as String? ??
                                                                        member['id']
                                                                            as String? ??
                                                                        l10n.restaurantCalendarEmployeeFallback,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                            onChanged:
                                                                !offlineSnapshot &&
                                                                    _savingTaskId ==
                                                                        null &&
                                                                    _savingPartId ==
                                                                        null &&
                                                                    _assigningDate == null &&
                                                                    _reschedulingTaskId == null
                                                                ? (
                                                                    value,
                                                                  ) => _assignPart(
                                                                    task,
                                                                    part,
                                                                    value?.isEmpty ==
                                                                            true
                                                                        ? null
                                                                        : value,
                                                                  )
                                                                : null,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        if (_savingTaskId == taskId)
                                          const LinearProgressIndicator(
                                            minHeight: 2,
                                          ),
                                        if (_savingPartId != null &&
                                            parts.any(
                                              (part) =>
                                                  part['id'] == _savingPartId,
                                            ))
                                          const LinearProgressIndicator(
                                            minHeight: 2,
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

DateTime _monday(String date) {
  final parsed = DateTime.tryParse('${date}T12:00:00Z')?.toUtc() ??
      DateTime.now().toUtc();
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
  ).subtract(Duration(days: parsed.weekday - DateTime.monday));
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _status(String status, AppLocalizations l10n) => switch (status) {
  'in_progress' => l10n.restaurantCalendarStatusInProgress,
  'paused' => l10n.restaurantCalendarStatusPaused,
  'blocked' => l10n.restaurantCalendarStatusBlocked,
  'completed' => l10n.restaurantCalendarStatusCompleted,
  _ => l10n.restaurantCalendarStatusPending,
};

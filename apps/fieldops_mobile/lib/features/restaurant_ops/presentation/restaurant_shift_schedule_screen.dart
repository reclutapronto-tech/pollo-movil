import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantShiftScheduleScreen extends ConsumerStatefulWidget {
  const RestaurantShiftScheduleScreen({
    super.key,
    required this.branchId,
    required this.initialDate,
    required this.branchTimeZone,
  });

  final String branchId;
  final String initialDate;
  final String branchTimeZone;

  @override
  ConsumerState<RestaurantShiftScheduleScreen> createState() =>
      _RestaurantShiftScheduleScreenState();
}

class _RestaurantShiftScheduleScreenState
    extends ConsumerState<RestaurantShiftScheduleScreen> {
  late DateTime _weekStart;
  late Future<OpsJson> _schedule;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(
      DateTime.tryParse(widget.initialDate) ?? DateTime.now(),
    );
    _schedule = _fetch();
  }

  static DateTime _monday(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<OpsJson> _fetch() => ref
      .read(restaurantOpsRepositoryProvider)
      .fetchShiftSchedule(widget.branchId, _iso(_weekStart));

  Future<void> _refresh() async {
    final request = _fetch();
    setState(() => _schedule = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the request failure and offers a retry.
    }
  }

  void _moveWeek(int weeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: weeks * 7));
      _schedule = _fetch();
    });
  }

  Future<void> _editShift({
    required List<Map<String, dynamic>> employees,
    required DateTime date,
    Map<String, dynamic>? shift,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final draft = await showDialog<_ShiftDraft>(
      context: context,
      builder: (_) =>
          _ShiftEditorDialog(employees: employees, date: date, shift: shift),
    );
    if (draft == null || !mounted) return;
    setState(() => _busyId = shift?['id'] as String? ?? 'new');
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .saveShift(
            branchId: widget.branchId,
            shiftId: shift?['id'] as String?,
            employeeId: draft.employeeId,
            shiftDate: _iso(draft.date),
            startTime: draft.startTime,
            endTime: draft.endTime,
            status: draft.published ? 'published' : 'draft',
            breaks: draft.breaks,
          );
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _schedule = _fetch();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shift == null
                ? l10n.restaurantShiftSaved
                : l10n.restaurantShiftUpdated,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.restaurantShiftSaveError(error.toString())),
        ),
      );
    }
  }

  Future<void> _cancelShift(Map<String, dynamic> shift) async {
    final l10n = AppLocalizations.of(context)!;
    final employeeName =
        shift['employee_name'] as String? ?? l10n.restaurantShiftTeamMember;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restaurantShiftCancelTitle),
        content: Text(l10n.restaurantShiftCancelConfirmation(employeeName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.restaurantShiftCancelAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = shift['id'] as String;
    setState(() => _busyId = id);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .cancelShift(branchId: widget.branchId, shiftId: id);
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _schedule = _fetch();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.restaurantShiftCanceled)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.restaurantShiftCancelError(error.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      _,
      next,
    ) {
      if (next.hasValue && _busyId == null) _refresh();
    });
    final days = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.restaurantShiftScheduleTitle)),
      body: FutureBuilder<OpsJson>(
        future: _schedule,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.restaurantShiftLoadError),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _schedule = _fetch()),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final offlineSnapshot = data['_offline_snapshot'] == true;
          final employees = (data['employees'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final shifts = (data['shifts'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          return Column(
            children: [
              if (offlineSnapshot)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(l10n.restaurantShiftOfflineNotice),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.restaurantShiftPreviousWeek,
                      onPressed: _busyId == null ? () => _moveWeek(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${MaterialLocalizations.of(context).formatMediumDate(days.first)} – ${MaterialLocalizations.of(context).formatMediumDate(days.last)}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.restaurantShiftNextWeek,
                      onPressed: _busyId == null ? () => _moveWeek(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l10n.restaurantShiftTimezone(widget.branchTimeZone),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      final dayShifts = shifts
                          .where((shift) => shift['shift_date'] == _iso(day))
                          .toList();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
                                  IconButton(
                                    tooltip: l10n.restaurantShiftAdd,
                                    onPressed:
                                        offlineSnapshot ||
                                            employees.isEmpty ||
                                            _busyId != null
                                        ? null
                                        : () => _editShift(
                                            employees: employees,
                                            date: day,
                                          ),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                              if (dayShifts.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(l10n.restaurantShiftNoShifts),
                                ),
                              ...dayShifts.map((shift) {
                                final shiftId = shift['id'] as String;
                                final breaks =
                                    (shift['breaks'] as List<dynamic>? ??
                                            const [])
                                        .whereType<Map<String, dynamic>>()
                                        .map(
                                          (item) =>
                                              '${_time(item['start_time'])}–${_time(item['end_time'])}',
                                        )
                                        .join(', ');
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    shift['employee_name'] as String? ??
                                        l10n.restaurantShiftTeamMember,
                                  ),
                                  subtitle: Text(
                                    '${l10n.restaurantShiftTimeRange(_time(shift['start_time']), _time(shift['end_time']))} · ${shift['status'] == 'published' ? l10n.restaurantShiftPublished : l10n.restaurantShiftDraft}${breaks.isEmpty ? '' : '\n${l10n.restaurantShiftBreaks(breaks)}'}',
                                  ),
                                  isThreeLine: breaks.isNotEmpty,
                                  trailing: _busyId == shiftId
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : PopupMenuButton<String>(
                                          enabled:
                                              !offlineSnapshot &&
                                              _busyId == null,
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _editShift(
                                                employees: employees,
                                                date: day,
                                                shift: shift,
                                              );
                                            } else {
                                              _cancelShift(shift);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text(
                                                l10n.restaurantShiftEdit,
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'cancel',
                                              child: Text(
                                                l10n.restaurantShiftCancelAction,
                                              ),
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

  static String _time(Object? value) {
    final text = value?.toString() ?? '';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }
}

class _ShiftDraft {
  const _ShiftDraft({
    required this.employeeId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.published,
    required this.breaks,
  });

  final String employeeId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final bool published;
  final List<OpsJson> breaks;
}

class _ShiftEditorDialog extends StatefulWidget {
  const _ShiftEditorDialog({
    required this.employees,
    required this.date,
    this.shift,
  });

  final List<Map<String, dynamic>> employees;
  final DateTime date;
  final Map<String, dynamic>? shift;

  @override
  State<_ShiftEditorDialog> createState() => _ShiftEditorDialogState();
}

class _ShiftEditorDialogState extends State<_ShiftEditorDialog> {
  late String? _employeeId;
  late DateTime _date;
  late TimeOfDay? _start;
  late TimeOfDay? _end;
  late bool _published;
  late List<({TimeOfDay? start, TimeOfDay? end})> _breaks;

  @override
  void initState() {
    super.initState();
    final shift = widget.shift;
    final employeeId = shift?['employee_id'] as String?;
    _employeeId =
        widget.employees.any((employee) => employee['user_id'] == employeeId)
        ? employeeId
        : null;
    _date =
        DateTime.tryParse(shift?['shift_date'] as String? ?? '') ?? widget.date;
    _start = _parseTime(shift?['start_time']);
    _end = _parseTime(shift?['end_time']);
    _published = shift?['status'] == 'published';
    _breaks = ((shift?['breaks'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => (
            start: _parseTime(item['start_time']),
            end: _parseTime(item['end_time']),
          ),
        )
        .toList();
  }

  static TimeOfDay? _parseTime(Object? value) {
    if (value is! String || value.length < 5) return null;
    final parts = value.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(TimeOfDay? current) =>
      showTimePicker(context: context, initialTime: current ?? TimeOfDay.now());

  Future<void> _pickBreakTime(int index, {required bool start}) async {
    final current = start ? _breaks[index].start : _breaks[index].end;
    final value = await _pickTime(current);
    if (value == null || !mounted) return;
    setState(() {
      final item = _breaks[index];
      _breaks[index] = (
        start: start ? value : item.start,
        end: start ? item.end : value,
      );
    });
  }

  void _save() {
    if (_employeeId == null ||
        _start == null ||
        _end == null ||
        _breaks.any((item) => item.start == null || item.end == null))
      return;
    Navigator.of(context).pop(
      _ShiftDraft(
        employeeId: _employeeId!,
        date: _date,
        startTime: _formatTime(_start!),
        endTime: _formatTime(_end!),
        published: _published,
        breaks: _breaks
            .map(
              (item) => <String, dynamic>{
                'start_time': _formatTime(item.start!),
                'end_time': _formatTime(item.end!),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final weekStart = _RestaurantShiftScheduleScreenState._monday(widget.date);
    final weekDates = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final validDate = weekDates.any(
      (day) =>
          _RestaurantShiftScheduleScreenState._iso(day) ==
          _RestaurantShiftScheduleScreenState._iso(_date),
    );
    if (!validDate) _date = widget.date;
    final canSave =
        _employeeId != null &&
        _start != null &&
        _end != null &&
        _breaks.length <= 8 &&
        _breaks.every((item) => item.start != null && item.end != null);
    return AlertDialog(
      title: Text(
        widget.shift == null
            ? l10n.restaurantShiftAddDialogTitle
            : l10n.restaurantShiftEditDialogTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _employeeId,
              decoration: InputDecoration(
                labelText: l10n.restaurantShiftEmployee,
              ),
              items: widget.employees
                  .map(
                    (employee) => DropdownMenuItem(
                      value: employee['user_id'] as String,
                      child: Text(
                        employee['full_name'] as String? ??
                            l10n.restaurantShiftTeamMember,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _employeeId = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _RestaurantShiftScheduleScreenState._iso(_date),
              decoration: InputDecoration(labelText: l10n.restaurantShiftDay),
              items: weekDates
                  .map(
                    (day) => DropdownMenuItem(
                      value: _RestaurantShiftScheduleScreenState._iso(day),
                      child: Text(
                        MaterialLocalizations.of(context).formatMediumDate(day),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                final selected = DateTime.tryParse(value ?? '');
                if (selected != null) setState(() => _date = selected);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final value = await _pickTime(_start);
                    if (value != null && mounted)
                      setState(() => _start = value);
                  },
                  child: Text(
                    _start == null
                        ? l10n.restaurantShiftStartChoose
                        : '${l10n.restaurantShiftStart}: ${_start!.format(context)}',
                  ),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final value = await _pickTime(_end);
                    if (value != null && mounted) setState(() => _end = value);
                  },
                  child: Text(
                    _end == null
                        ? l10n.restaurantShiftEndChoose
                        : '${l10n.restaurantShiftEnd}: ${_end!.format(context)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.restaurantShiftPublish),
              subtitle: Text(l10n.restaurantShiftDraftDescription),
              value: _published,
              onChanged: (value) => setState(() => _published = value),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text(l10n.restaurantShiftBreaksTitle)),
                TextButton.icon(
                  onPressed: _breaks.length >= 8
                      ? null
                      : () => setState(
                          () => _breaks.add((start: null, end: null)),
                        ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.restaurantShiftAddBreak),
                ),
              ],
            ),
            ..._breaks.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _pickBreakTime(index, start: true),
                      child: Text(
                        item.start == null
                            ? l10n.restaurantShiftStart
                            : item.start!.format(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _pickBreakTime(index, start: false),
                      child: Text(
                        item.end == null
                            ? l10n.restaurantShiftEnd
                            : item.end!.format(context),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.restaurantShiftRemoveBreak,
                    onPressed: () => setState(() => _breaks.removeAt(index)),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: Text(l10n.restaurantShiftSave),
        ),
      ],
    );
  }
}

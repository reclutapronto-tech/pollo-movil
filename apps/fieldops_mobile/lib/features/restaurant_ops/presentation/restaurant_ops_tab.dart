import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_calendar_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_evidence_capture_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_notifications_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_area_inspection_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_absence_review_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_branch_structure_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_shift_schedule_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_shift_coverage_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_team_directory_screen.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_sync_recovery_panel.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_sync_status_button.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum RestaurantOpsSection { shift, waste, incidents, handoff }

class RestaurantOpsTab extends ConsumerWidget {
  const RestaurantOpsTab({super.key, required this.section});

  final RestaurantOpsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final branches = ref.watch(restaurantBranchesProvider);
    return branches.when(
      loading: () => const _OpsLoading(),
      error: (error, _) => _OpsMessage(
        title: l10n.restaurantOpsBranchesLoadError,
        message: error.toString(),
        onRetry: () => ref.invalidate(restaurantBranchesProvider),
      ),
      data: (items) {
        if (items.isEmpty) return const _BranchNotConfigured();
        final selectedBranchId = ref.watch(restaurantSelectedBranchProvider);
        final branch = items.firstWhere(
          (item) => item['id'] == selectedBranchId,
          orElse: () => items.first,
        );
        final branchId = branch['id'] as String;
        ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(branchId), (
          previous,
          next,
        ) {
          if (next.hasValue) {
            ref.invalidate(restaurantDashboardProvider(branchId));
            ref.invalidate(restaurantNotificationsProvider(branchId));
            ref.invalidate(restaurantBranchesProvider);
          }
        });
        final dashboard = ref.watch(restaurantDashboardProvider(branchId));
        return dashboard.when(
          loading: () => const _OpsLoading(),
          error: (error, _) => _OpsMessage(
            title: l10n.restaurantOpsShiftLoadError,
            message: error.toString(),
            onRetry: () =>
                ref.invalidate(restaurantDashboardProvider(branchId)),
          ),
          data: (data) => _RestaurantSection(
            section: section,
            branchId: branchId,
            branchName:
                (data['branch'] as Map<String, dynamic>?)?['name'] as String? ??
                l10n.restaurantOpsBranchFallback,
            branchOptions: items,
            onBranchSelected: (value) => ref
                .read(restaurantSelectedBranchProvider.notifier)
                .selectBranch(value),
            data: data,
            onRefresh: () async =>
                ref.invalidate(restaurantDashboardProvider(branchId)),
          ),
        );
      },
    );
  }
}

class _RestaurantSection extends ConsumerStatefulWidget {
  const _RestaurantSection({
    required this.section,
    required this.branchId,
    required this.branchName,
    required this.branchOptions,
    required this.onBranchSelected,
    required this.data,
    required this.onRefresh,
  });

  final RestaurantOpsSection section;
  final String branchId;
  final String branchName;
  final List<Map<String, dynamic>> branchOptions;
  final ValueChanged<String> onBranchSelected;
  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_RestaurantSection> createState() => _RestaurantSectionState();
}

class _OfflineSnapshotNotice extends StatelessWidget {
  const _OfflineSnapshotNotice({this.savedAt});

  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localTime = savedAt?.toLocal();
    final timeLabel = localTime == null
        ? ''
        : '${MaterialLocalizations.of(context).formatShortDate(localTime)} · '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: ListTile(
          leading: const Icon(Icons.cloud_off_rounded),
          title: Text(l10n.restaurantOpsOfflineTitle),
          subtitle: Text(
            timeLabel.isEmpty
                ? l10n.restaurantOpsOfflinePendingChanges
                : l10n.restaurantOpsOfflineSnapshotAt(timeLabel),
          ),
        ),
      ),
    );
  }
}

class _RestaurantSectionState extends ConsumerState<_RestaurantSection> {
  final _incidentController = TextEditingController();
  final _handoffNoteController = TextEditingController();
  final _absenceNoteController = TextEditingController();
  final Map<String, String?> _binStates = {};
  String? _areaId;
  String? _handoffRecipientId;
  String? _handoffClientEventId;
  DateTime? _absenceStartDate;
  DateTime? _absenceEndDate;
  String _urgency = 'normal';
  bool _blocking = false;
  bool _saving = false;

  @override
  void dispose() {
    _incidentController.dispose();
    _handoffNoteController.dispose();
    _absenceNoteController.dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) => switch (widget.section) {
    RestaurantOpsSection.shift => l10n.restaurantOpsShiftTitle,
    RestaurantOpsSection.waste => l10n.restaurantOpsWasteTitle,
    RestaurantOpsSection.incidents => l10n.restaurantOpsIncidentsTitle,
    RestaurantOpsSection.handoff => l10n.restaurantOpsHandoffTitle,
  };

  Future<void> _run(Future<Map<String, dynamic>> Function() operation) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      final result = await operation();
      if (!mounted) return;
      final queued = result['queued'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued ? l10n.restaurantOpsSavedOffline : l10n.restaurantOpsSaved,
          ),
        ),
      );
      await widget.onRefresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deliverHandoff(String? recipientId) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .deliverHandoff(
            branchId: widget.branchId,
            clientEventId: _handoffClientEventId ??= ref
                .read(restaurantOpsRepositoryProvider)
                .createClientEventId(),
            recipientId: recipientId,
            note: _handoffNoteController.text.trim(),
          );
      if (!mounted) return;
      _handoffClientEventId = null;
      _handoffNoteController.clear();
      setState(() => _handoffRecipientId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantOpsHandoffDelivered)),
      );
      await widget.onRefresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAbsenceDate({required bool isStart}) async {
    final existing = isStart ? _absenceStartDate : _absenceEndDate;
    final reference = isStart ? _absenceEndDate : _absenceStartDate;
    final chosen = await showDatePicker(
      context: context,
      initialDate: existing ?? reference ?? DateTime.now(),
      firstDate: isStart
          ? DateTime(2000)
          : (_absenceStartDate ?? DateTime(2000)),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    final dateOnly = DateTime(chosen.year, chosen.month, chosen.day);
    setState(() {
      if (isStart) {
        _absenceStartDate = dateOnly;
        if (_absenceEndDate == null || _absenceEndDate!.isBefore(dateOnly)) {
          _absenceEndDate = dateOnly;
        }
      } else {
        _absenceEndDate = dateOnly;
      }
    });
  }

  Future<void> _requestAbsence() async {
    final start = _absenceStartDate;
    final end = _absenceEndDate;
    if (_saving || start == null || end == null) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(restaurantOpsRepositoryProvider)
          .requestAbsence(
            branchId: widget.branchId,
            startDate: _isoDate(start),
            endDate: _isoDate(end),
            note: _absenceNoteController.text.trim(),
          );
      if (!mounted) return;
      _absenceNoteController.clear();
      setState(() {
        _absenceStartDate = null;
        _absenceEndDate = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['queued'] == true
                ? 'Solicitud guardada en el teléfono; se enviará al recuperar conexión.'
                : 'Solicitud enviada para revisión.',
          ),
        ),
      );
      await widget.onRefresh();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAreaInspection(Map<String, dynamic> template) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RestaurantAreaInspectionScreen(
          branchId: widget.branchId,
          template: template,
        ),
      ),
    );
    if (saved == true && mounted) await widget.onRefresh();
  }

  void _openNotificationTarget(Map<String, dynamic> notification) {
    final type = notification['notification_type'] as String? ?? '';
    final payload = notification['data'] is Map
        ? Map<String, dynamic>.from(notification['data'] as Map)
        : const <String, dynamic>{};
    final localDate = widget.data['local_date'] as String? ?? '';
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final currentMember = _maps(widget.data['members']).firstWhere(
      (member) => member['user_id'] == userId,
      orElse: () => <String, dynamic>{},
    );
    final canManage = const {
      'admin',
      'supervisor',
    }.contains(currentMember['access_role'] as String?);
    final branchTimezone =
        (widget.data['branch'] as Map<String, dynamic>?)?['timezone']
            as String? ??
        'local';

    if (type == 'task_assigned' || type == 'task_part_assigned') {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RestaurantCalendarScreen(
            branchId: widget.branchId,
            initialDate: payload['scheduled_for'] as String? ?? localDate,
            canManage: canManage,
            highlightTaskId:
                payload['task_id'] as String? ??
                notification['entity_id'] as String?,
          ),
        ),
      );
      return;
    }
    if (type.startsWith('incident_')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              const RestaurantOpsTab(section: RestaurantOpsSection.incidents),
        ),
      );
      return;
    }
    if (type.startsWith('shift_handoff_')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              const RestaurantOpsTab(section: RestaurantOpsSection.handoff),
        ),
      );
      return;
    }
    if (type.startsWith('shift_cover_')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RestaurantShiftCoverageScreen(
            branchId: widget.branchId,
          ),
        ),
      );
      return;
    }
    if (type.startsWith('shift_')) {
      if (!canManage) {
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                const RestaurantOpsTab(section: RestaurantOpsSection.shift),
          ),
        );
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RestaurantShiftScheduleScreen(
            branchId: widget.branchId,
            initialDate: payload['shift_date'] as String? ?? localDate,
            branchTimeZone: branchTimezone,
          ),
        ),
      );
      return;
    }
    if (type == 'absence_requested') {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RestaurantAbsenceReviewScreen(
            branchId: widget.branchId,
            onReviewed: () {
              ref.invalidate(restaurantDashboardProvider(widget.branchId));
              ref.invalidate(restaurantNotificationsProvider(widget.branchId));
            },
          ),
        ),
      );
      return;
    }
    if (type == 'inspection_attention' ||
        type == 'inspection_due' ||
        type.startsWith('waste_')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              const RestaurantOpsTab(section: RestaurantOpsSection.waste),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            const RestaurantOpsTab(section: RestaurantOpsSection.shift),
      ),
    );
  }

  Future<void> _taskAction(
    Map<String, dynamic> task,
    String action, {
    String? partId,
  }) async {
    String? note;
    if (action == 'pause') {
      note = await _requestPauseReason();
      if (note == null || !mounted) return;
    }
    String? evidencePath;
    if (action == 'complete' && task['requires_evidence'] == true) {
      final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const RestaurantEvidenceCaptureScreen(),
        ),
      );
      if (path == null || !mounted) return;
      try {
        evidencePath = await ref
            .read(restaurantOpsRepositoryProvider)
            .uploadEvidence(
              branchId: widget.branchId,
              taskId: task['id'] as String,
              partId: partId,
              filePath: path,
            );
      } on Object catch (error) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        return;
      }
    }
    final actualAction = action == 'complete' && task['task_source'] == 'waste'
        ? 'bag_changed'
        : action;
    await _run(
      () => ref
          .read(restaurantOpsRepositoryProvider)
          .taskAction(
            branchId: widget.branchId,
            taskId: task['id'] as String,
            partId: partId,
            action: actualAction,
            note: note,
            evidencePath: evidencePath,
          ),
    );
  }

  Future<String?> _requestPauseReason() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(l10n.restaurantOpsPauseTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.restaurantOpsPauseOptionalNote,
                hintText: l10n.restaurantOpsPauseHint,
              ),
              onChanged: (_) => setDialogState(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.restaurantOpsPauseContinue),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: Text(l10n.restaurantOpsPauseAction),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final pendingEvents = ref
        .watch(restaurantOutboxEventsProvider(widget.branchId))
        .maybeWhen(data: (events) => events, orElse: () => const <PendingEvent>[]);
    final taskDisplayData = userId == null
        ? widget.data
        : projectPendingRestaurantTaskActions(
            dashboard: widget.data,
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final displayData = userId == null
        ? taskDisplayData
        : projectPendingRestaurantIncidentUpdates(
            dashboard: taskDisplayData,
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final pendingWasteReview = userId == null
        ? null
        : pendingRestaurantWasteInspection(
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final pendingAreaInspections = userId == null
        ? const <String, OpsJson>{}
        : pendingRestaurantAreaInspections(
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final pendingIncidents = userId == null
        ? const <OpsJson>[]
        : pendingRestaurantIncidents(
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final pendingHandoffAcknowledgements = userId == null
        ? const <String, bool>{}
        : pendingRestaurantHandoffAcknowledgements(
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final pendingAbsenceRequests = userId == null
        ? const <OpsJson>[]
        : pendingRestaurantAbsenceRequests(
            events: pendingEvents,
            branchId: widget.branchId,
            actorId: userId,
          );
    final notificationInbox = ref.watch(
      restaurantNotificationsProvider(widget.branchId),
    );
    final unreadCount = notificationInbox.maybeWhen(
      data: (data) {
        if (userId == null) return (data['unread_count'] as num? ?? 0).toInt();
        final projected = projectPendingRestaurantNotificationReads(
          inbox: data,
          events: pendingEvents,
          branchId: widget.branchId,
          actorId: userId,
        );
        return (projected['unread_count'] as num? ?? 0).toInt();
      },
      orElse: () => 0,
    );
    final body = switch (widget.section) {
      RestaurantOpsSection.shift => _shiftContent(
        userId,
        displayData,
        pendingAbsenceRequests,
      ),
      RestaurantOpsSection.waste => _wasteContent(
        pendingWasteReview,
        pendingAreaInspections,
      ),
      RestaurantOpsSection.incidents =>
        _incidentContent(displayData, pendingIncidents),
      RestaurantOpsSection.handoff => _handoffContent(
        userId,
        pendingHandoffAcknowledgements,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(l10n)),
            Text(
              widget.branchName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          const RestaurantSyncStatusButton(),
          if (widget.branchOptions.length > 1)
            PopupMenuButton<String>(
              tooltip: l10n.restaurantOpsSwitchBranch,
              icon: const Icon(Icons.storefront_outlined),
              onSelected: widget.onBranchSelected,
              itemBuilder: (context) => widget.branchOptions
                  .map(
                    (branch) => PopupMenuItem<String>(
                      value: branch['id'] as String,
                      child: Text(
                        branch['name'] as String? ??
                            l10n.restaurantOpsBranchFallback,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          IconButton(
            tooltip: l10n.restaurantNotificationsTitle,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => RestaurantNotificationsScreen(
                  branchId: widget.branchId,
                  branchName: widget.branchName,
                  onOpenNotification: _openNotificationTarget,
                ),
              ),
            ),
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            tooltip: l10n.restaurantOpsRefresh,
            onPressed: () => widget.onRefresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (widget.data['_offline_snapshot'] == true)
              _OfflineSnapshotNotice(
                savedAt: DateTime.tryParse(
                  widget.data['_snapshot_saved_at'] as String? ?? '',
                ),
              ),
            const RestaurantSyncRecoveryPanel(),
            ...body,
          ],
        ),
      ),
    );
  }

  List<Widget> _shiftContent(
    String? userId,
    Map<String, dynamic> data,
    List<OpsJson> pendingAbsenceRequests,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final tasks = _maps(data['tasks']);
    final ownTasks = tasks.where((task) {
      if (task['assigned_to'] == userId) return true;
      return _maps(task['parts']).any((part) => part['assigned_to'] == userId);
    }).toList();
    final localDate = data['local_date'] as String? ?? '';
    final shifts = _maps(data['shifts'])
        .where(
          (shift) =>
              shift['employee_id'] == userId &&
              ((shift['shift_date'] as String? ?? '').compareTo(localDate) >= 0 ||
                  shift['currently_active'] == true),
        )
        .toList();
    final members = _maps(data['members']);
    final matchingMembers = members.where((item) => item['user_id'] == userId);
    final member = matchingMembers.isEmpty ? null : matchingMembers.first;
    final serving = member?['customer_service_active'] == true;
    final canManage = const {
      'admin',
      'supervisor',
    }.contains(member?['access_role'] as String?);
    return [
      _SectionCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_rounded),
          title: Text(l10n.restaurantCalendarTitle),
          subtitle: Text(l10n.restaurantOpsCalendarDescription),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => RestaurantCalendarScreen(
                branchId: widget.branchId,
                initialDate: localDate,
                canManage: canManage,
              ),
            ),
          ),
        ),
      ),
      _SectionTitle(title: l10n.restaurantShiftScheduleTitle),
      if (shifts.isEmpty)
        _InfoCard(text: l10n.restaurantOpsNoUpcomingShifts)
      else
        ...shifts.take(10).map((shift) {
          final shiftDate = shift['shift_date'] as String? ?? '';
          final dateLabel = shift['currently_active'] == true
              ? l10n.restaurantCalendarStatusInProgress
              : shiftDate == localDate
              ? l10n.restaurantOpsToday
              : shiftDate == _dateOffset(localDate, 1)
              ? l10n.restaurantOpsTomorrow
              : shiftDate;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text('${shift['start_time']} – ${shift['end_time']}'),
                      ],
                    ),
                  ),
                  Text(l10n.restaurantShiftPublished),
                ],
              ),
            ),
          );
        }),
      _SectionTitle(
        title: Localizations.localeOf(context).languageCode == 'en'
            ? 'Shift coverage'
            : 'Cobertura de turnos',
      ),
      _SectionCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.swap_horiz_rounded),
          title: Text(
            Localizations.localeOf(context).languageCode == 'en'
                ? 'Shift coverage'
                : 'Cobertura de turnos',
          ),
          subtitle: Text(
            Localizations.localeOf(context).languageCode == 'en'
                ? 'Request coverage for a published shift or review branch requests.'
                : 'Solicita cobertura para un turno publicado o revisa solicitudes de la sucursal.',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => RestaurantShiftCoverageScreen(
                branchId: widget.branchId,
              ),
            ),
          ),
        ),
      ),
      _SectionTitle(title: l10n.restaurantOpsCustomerService),
      _SectionCard(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.restaurantOpsCustomerService),
          subtitle: Text(l10n.restaurantOpsInterruptibleWait),
          value: serving,
          onChanged: _saving
              ? null
              : (value) => _run(() async {
                  await ref
                      .read(restaurantOpsRepositoryProvider)
                      .setCustomerService(
                        branchId: widget.branchId,
                        active: value,
                      );
                  return {'saved': true};
                }),
        ),
      ),
      _SectionTitle(title: l10n.restaurantOpsOwnActivities),
      if (ownTasks.isEmpty) _InfoCard(text: l10n.restaurantOpsNoOwnActivities),
      ...ownTasks.map(_taskCard),
      if (canManage) ...[
        _SectionTitle(title: l10n.restaurantStructureTitle),
        _SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(l10n.restaurantStructureTitle),
            subtitle: Text(l10n.restaurantOpsBranchStructureDescription),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    RestaurantBranchStructureScreen(branchId: widget.branchId),
              ),
            ),
          ),
        ),
        _SectionTitle(title: l10n.restaurantTeamTitle),
        _SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: Text(l10n.restaurantTeamTitle),
            subtitle: Text(l10n.restaurantOpsTeamDescription),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    RestaurantTeamDirectoryScreen(branchId: widget.branchId),
              ),
            ),
          ),
        ),
        _SectionTitle(title: l10n.restaurantShiftScheduleTitle),
        _SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(l10n.restaurantShiftScheduleTitle),
            subtitle: Text(l10n.restaurantOpsShiftAdminDescription),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RestaurantShiftScheduleScreen(
                    branchId: widget.branchId,
                    initialDate: localDate,
                    branchTimeZone:
                        (data['branch'] as Map<String, dynamic>?)?['timezone']
                            as String? ??
                        'local',
                  ),
                ),
              );
              if (mounted)
                ref.invalidate(restaurantDashboardProvider(widget.branchId));
            },
          ),
        ),
        _SectionTitle(title: l10n.restaurantAbsenceReviewTitle),
        _SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available_outlined),
            title: Text(l10n.restaurantOpsPendingAbsences),
            subtitle: Text(l10n.restaurantOpsAbsenceReviewDescription),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => RestaurantAbsenceReviewScreen(
                  branchId: widget.branchId,
                  onReviewed: () {
                    ref.invalidate(
                      restaurantDashboardProvider(widget.branchId),
                    );
                    ref.invalidate(
                      restaurantNotificationsProvider(widget.branchId),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
      _SectionTitle(title: l10n.restaurantAbsenceReviewTitle),
      _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.restaurantOpsAbsencePendingNote),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickAbsenceDate(isStart: true),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      _absenceStartDate == null
                          ? l10n.restaurantOpsDateFrom
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_absenceStartDate!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickAbsenceDate(isStart: false),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _absenceEndDate == null
                          ? l10n.restaurantOpsDateUntil
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_absenceEndDate!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _absenceNoteController,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.restaurantOpsOptionalNote,
                alignLabelWithHint: true,
              ),
            ),
            _ActionButton(
              label: _saving
                  ? l10n.restaurantOpsAbsenceSending
                  : l10n.restaurantOpsAbsenceSend,
              onPressed:
                  _saving ||
                      _absenceStartDate == null ||
                      _absenceEndDate == null
                  ? null
                  : _requestAbsence,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.restaurantOpsAbsenceOfflineNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      ..._maps(data['my_absences']).map(
        (absence) => _SectionCard(
          child: Row(
            children: [
              const Icon(Icons.event_note_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_formatOpsDate(context, absence['start_date'] as String?)} – ${_formatOpsDate(context, absence['end_date'] as String?)}${absence['note'] is String && (absence['note'] as String).isNotEmpty ? '\n${absence['note']}' : ''}',
                ),
              ),
              Text(
                _absenceStatus(absence['status'] as String? ?? 'pending', l10n),
              ),
            ],
          ),
        ),
      ),
      if (pendingAbsenceRequests.isNotEmpty) ...[
        _SectionTitle(title: l10n.restaurantOpsSavedAbsencesTitle),
        ...pendingAbsenceRequests.map(
          (request) => _SectionCard(
            child: Row(
              children: [
                const Icon(Icons.cloud_upload_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_formatOpsDate(context, request['start_date'] as String?)} – ${_formatOpsDate(context, request['end_date'] as String?)}'
                    '${request['note'] is String && (request['note'] as String).isNotEmpty ? '\n${request['note']}' : ''}',
                  ),
                ),
                Text(
                  request['needs_attention'] == true
                      ? l10n.restaurantOpsSyncReviewNeeded
                      : l10n.restaurantOpsPendingSend,
                ),
              ],
            ),
          ),
        ),
      ],
      _SectionTitle(title: l10n.restaurantOpsUnassignedSection),
      ...tasks
          .where(
            (task) =>
                task['status'] != 'completed' &&
                task['assigned_to'] == null &&
                task['configuration_pending'] != true,
          )
          .map(_taskCard),
    ];
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final l10n = AppLocalizations.of(context)!;
    final name =
        task['name'] as String? ?? l10n.restaurantCalendarFallbackActivity;
    final parts = _maps(task['parts']);
    final assignedTo = task['assigned_to'] as String?;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            [
              if (task['area_name'] != null) task['area_name'],
              '${task['estimated_minutes'] ?? 0} min',
              _statusLabel(task['status'] as String? ?? 'pending', l10n),
            ].join(' · '),
          ),
          if (task['status'] == 'paused' && task['latest_pause_note'] is String)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.restaurantOpsPauseReason(
                  task['latest_pause_note'] as String,
                ),
              ),
            ),
          if (parts.isEmpty && task['_pending_sync'] == true)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(l10n.restaurantOpsTaskPendingSync),
            ),
          if (task['configuration_pending'] == true)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(l10n.restaurantCalendarConfigurationPending),
            ),
          if (parts.isNotEmpty) ...[
            const Divider(height: 24),
            ...parts.map((part) => _partRow(task, part)),
          ] else if (task['configuration_pending'] != true)
            _actionRow(task, assignedTo, null),
        ],
      ),
    );
  }

  Widget _partRow(Map<String, dynamic> task, Map<String, dynamic> part) {
    final l10n = AppLocalizations.of(context)!;
    final zone = part['zone_name'] as String? ?? l10n.restaurantOpsZoneFallback;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final owner =
        part['assignee_name'] as String? ??
        (currentUserId != null && part['assigned_to'] == currentUserId
            ? l10n.restaurantOpsYou
            : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$zone · ${part['estimated_minutes']} min'),
          Text(
            owner == null
                ? l10n.restaurantCalendarNoAssignee
                : l10n.restaurantOpsAssigneeNamed(owner),
          ),
          if (part['_pending_sync'] == true)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(l10n.restaurantOpsTaskPendingSync),
            ),
          if (part['status'] == 'paused' && part['latest_pause_note'] is String)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.restaurantOpsPauseReason(
                  part['latest_pause_note'] as String,
                ),
              ),
            ),
          _actionRow(
            task,
            part['assigned_to'] as String?,
            part['id'] as String,
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    Map<String, dynamic> task,
    String? assignee,
    String? partId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final status =
        (partId == null ? task['status'] : _partStatus(task, partId))
            as String? ??
        'pending';
    String? action;
    String label = '';
    if (assignee == null && status == 'pending') {
      action = 'claim';
      label = l10n.restaurantOpsActionClaim;
    } else if (assignee == userId && status == 'pending') {
      action = 'start';
      label = l10n.restaurantOpsActionStart;
    } else if (assignee == userId && status == 'in_progress') {
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: l10n.restaurantOpsActionPause,
              onPressed: () => _taskAction(task, 'pause', partId: partId),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              label: l10n.restaurantOpsActionComplete,
              onPressed: () => _taskAction(task, 'complete', partId: partId),
            ),
          ),
        ],
      );
    } else if (assignee == userId && status == 'paused') {
      action = 'resume';
      label = l10n.restaurantOpsActionResume;
    } else if (assignee == userId && status == 'blocked') {
      action = 'resume';
      label = l10n.restaurantOpsActionResume;
    }
    if (action == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _ActionButton(
        label: label,
        onPressed: () => _taskAction(task, action!, partId: partId),
      ),
    );
  }

  String _partStatus(Map<String, dynamic> task, String partId) =>
      _maps(task['parts']).firstWhere((part) => part['id'] == partId)['status']
          as String? ??
      'pending';

  List<Widget> _wasteContent(
    OpsJson? pendingReview,
    Map<String, OpsJson> pendingAreaInspections,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final bins = _maps(widget.data['waste_bins']);
    final hasPendingReview = pendingReview != null;
    final pendingStates =
        (pendingReview?['states'] as Map<String, String>?) ?? const {};
    final unconfiguredFullBins = bins
        .where(
          (bin) =>
              (hasPendingReview
                      ? pendingStates[bin['id']]
                      : _binStates[bin['id']]) ==
                  'full' &&
              bin['task_policy_configured'] != true,
        )
        .toList();
    final areaTemplates = _maps(widget.data['area_inspection_templates']);
    final areaInspections = _maps(widget.data['area_inspections']);
    return [
      _InfoCard(text: l10n.restaurantOpsWasteIntro),
      if (hasPendingReview)
        _InfoCard(
          text: pendingReview['needs_attention'] == true
              ? l10n.restaurantOpsWasteNeedsAttention
              : l10n.restaurantOpsWastePendingSync,
        ),
      _SectionTitle(title: l10n.restaurantOpsWasteStatusTitle),
      ...bins.map((bin) {
        final id = bin['id'] as String;
        final value = hasPendingReview ? pendingStates[id] : _binStates[id];
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bin['name'] as String? ?? l10n.restaurantOpsBinFallback,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (bin['inspection_interval_minutes'] != null)
                Text(
                  l10n.restaurantOpsIntervalConfigured(
                    bin['inspection_interval_minutes'].toString(),
                  ),
                ),
              if (bin['inspection_due'] == true)
                Text(l10n.restaurantOpsInspectionDue),
              if (bin['task_policy_configured'] != true)
                Text(l10n.restaurantOpsWasteNeedsPolicy),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: value,
                decoration: InputDecoration(
                  labelText: l10n.restaurantOpsDeclaredState,
                ),
                hint: Text(l10n.restaurantOpsSelectState),
                items: [
                  DropdownMenuItem(
                    value: 'low',
                    child: Text(l10n.restaurantOpsBinLow),
                  ),
                  DropdownMenuItem(
                    value: 'half',
                    child: Text(l10n.restaurantOpsBinHalf),
                  ),
                  DropdownMenuItem(
                    value: 'full',
                    child: Text(l10n.restaurantOpsBinFull),
                  ),
                ],
                onChanged: hasPendingReview
                    ? null
                    : (next) => setState(() => _binStates[id] = next),
              ),
            ],
          ),
        );
      }),
      if (unconfiguredFullBins.isNotEmpty)
        _InfoCard(text: l10n.restaurantOpsCannotSaveFullBin),
      const SizedBox(height: 8),
      _ActionButton(
        label: hasPendingReview
            ? l10n.restaurantOpsWastePendingAction
            : _saving
            ? l10n.restaurantOpsSaving
            : l10n.restaurantOpsWasteSubmit,
        onPressed:
            hasPendingReview ||
                _saving ||
                bins.isEmpty ||
                bins.any((bin) => _binStates[bin['id']] == null) ||
                unconfiguredFullBins.isNotEmpty
            ? null
            : () => _run(
                () => ref
                    .read(restaurantOpsRepositoryProvider)
                    .inspectWaste(
                      branchId: widget.branchId,
                      results: bins
                          .map(
                            (bin) => {
                              'bin_id': bin['id'],
                              'state': _binStates[bin['id']],
                            },
                          )
                          .toList(),
                    ),
              ),
      ),
      const SizedBox(height: 8),
      _SectionTitle(title: l10n.restaurantOpsAreaInspectionsTitle),
      if (areaTemplates.isEmpty)
        _InfoCard(text: l10n.restaurantOpsNoInspectionTemplates),
      ...areaTemplates.map((template) {
        final items = _maps(template['items']);
        final pendingInspection = pendingAreaInspections[template['id']];
        final pendingResults = _maps(pendingInspection?['results']);
        final attentionCount = pendingResults
            .where((result) => result['result_state'] == 'needs_attention')
            .length;
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template['name'] as String? ??
                    l10n.restaurantOpsInspectionFallback,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (template['area_name'] is String)
                Text(template['area_name'] as String),
              Text(
                [
                  l10n.restaurantOpsInspectionCriteriaCount(items.length),
                  if (template['inspection_interval_minutes'] != null)
                    l10n.restaurantOpsInspectionInterval(
                      template['inspection_interval_minutes'].toString(),
                    ),
                ].join(' · '),
              ),
              if (template['inspection_due'] == true)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(l10n.restaurantOpsInspectionDue),
                ),
              if (pendingInspection != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    pendingInspection['needs_attention'] == true
                        ? l10n.restaurantOpsInspectionNeedsAttention
                        : l10n.restaurantOpsInspectionPendingSync(
                            attentionCount,
                          ),
                  ),
                ),
              const SizedBox(height: 10),
              _ActionButton(
                label: pendingInspection == null
                    ? l10n.restaurantOpsDoInspection
                    : l10n.restaurantOpsInspectionPendingAction,
                onPressed: items.isEmpty || pendingInspection != null
                    ? null
                    : () => _openAreaInspection(template),
              ),
            ],
          ),
        );
      }),
      if (areaInspections.isNotEmpty) ...[
        _SectionTitle(
          title: l10n.restaurantOpsRecentInspections(areaInspections.length),
        ),
        ...areaInspections.take(8).map((inspection) {
          final attentionItems = _maps(inspection['results'])
              .where((result) => result['result_state'] == 'needs_attention')
              .toList(growable: false);
          return _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      (inspection['needs_attention_count'] as num? ?? 0) > 0
                          ? Icons.warning_amber_rounded
                          : Icons.fact_check_outlined,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${inspection['template_name'] ?? l10n.restaurantOpsInspectionFallback} · ${inspection['inspector_name'] ?? l10n.restaurantOpsTeamFallback} · ${_formatOpsDate(context, inspection['inspection_date'] as String?)}',
                      ),
                    ),
                    Text(
                      (inspection['needs_attention_count'] as num? ?? 0) > 0
                          ? l10n.restaurantOpsNeedsAttentionCount(
                              (inspection['needs_attention_count'] as num? ?? 0)
                                  .toInt(),
                            )
                          : l10n.restaurantOpsNoAlerts,
                    ),
                  ],
                ),
                ...attentionItems
                    .take(4)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(top: 6, left: 34),
                        child: Text(
                          item['note'] is String &&
                                  (item['note'] as String).isNotEmpty
                              ? l10n.restaurantOpsCriterionNote(
                                  item['item_label'] as String? ??
                                      l10n.restaurantOpsCriterionFallback,
                                  item['note'] as String,
                                )
                              : item['item_label'] as String? ??
                                    l10n.restaurantOpsCriterionFallback,
                        ),
                      ),
                    ),
              ],
            ),
          );
        }),
      ],
    ];
  }

  List<Widget> _incidentContent(
    OpsJson displayData,
    List<OpsJson> pendingIncidents,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final areas = _maps(displayData['areas']);
    final incidents = _maps(displayData['incidents']);
    final members = _maps(displayData['members']);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final matchingMembers = members.where(
      (member) => member['user_id'] == userId,
    );
    final currentMember = matchingMembers.isEmpty
        ? null
        : matchingMembers.first;
    final canManage = const {
      'admin',
      'supervisor',
    }.contains(currentMember?['access_role'] as String?);
    return [
      _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.restaurantOpsIncidentReport),
            const SizedBox(height: 12),
            TextField(
              controller: _incidentController,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: l10n.restaurantOpsIncidentDescription,
              ),
              onChanged: (_) => setState(() {}),
            ),
            DropdownButtonFormField<String?>(
              value: _areaId,
              decoration: InputDecoration(
                labelText: l10n.restaurantOpsIncidentAreaOptional,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.restaurantOpsIncidentNoArea),
                ),
                ...areas.map(
                  (area) => DropdownMenuItem<String?>(
                    value: area['id'] as String,
                    child: Text(area['name'] as String? ?? ''),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _areaId = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _urgency,
              decoration: InputDecoration(labelText: l10n.restaurantOpsUrgency),
              items: [
                DropdownMenuItem(
                  value: 'low',
                  child: Text(l10n.restaurantOpsUrgencyLow),
                ),
                DropdownMenuItem(
                  value: 'normal',
                  child: Text(l10n.restaurantOpsUrgencyNormal),
                ),
                DropdownMenuItem(
                  value: 'high',
                  child: Text(l10n.restaurantOpsUrgencyHigh),
                ),
                DropdownMenuItem(
                  value: 'urgent',
                  child: Text(l10n.restaurantOpsUrgencyUrgent),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _urgency = value ?? 'normal'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.restaurantOpsIncidentBlocksWork),
              value: _blocking,
              onChanged: (value) => setState(() => _blocking = value ?? false),
            ),
            _ActionButton(
              label: _saving
                  ? l10n.restaurantOpsSaving
                  : l10n.restaurantOpsIncidentSend,
              onPressed: _saving || _incidentController.text.trim().length < 3
                  ? null
                  : () => _run(() async {
                      final result = await ref
                          .read(restaurantOpsRepositoryProvider)
                          .createIncident(
                            branchId: widget.branchId,
                            description: _incidentController.text.trim(),
                            areaId: _areaId,
                            urgency: _urgency,
                            isBlocking: _blocking,
                          );
                      if (mounted) {
                        _incidentController.clear();
                        setState(() {
                          _areaId = null;
                          _urgency = 'normal';
                          _blocking = false;
                        });
                      }
                      return result;
                    }),
            ),
          ],
        ),
      ),
      _SectionTitle(title: l10n.restaurantOpsOpenIncidents),
      if (incidents.isEmpty) _InfoCard(text: l10n.restaurantOpsNoOpenIncidents),
      ...incidents.map(
        (incident) => _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                incident['description'] as String? ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                [
                  if (incident['area_name'] != null) incident['area_name'],
                  _incidentUrgencyLabel(
                    incident['urgency'] as String? ?? 'normal',
                    l10n,
                  ),
                  incident['assignee_name'],
                  _incidentStatusLabel(
                    incident['status'] as String? ?? 'open',
                    l10n,
                  ),
                  if (incident['_pending_sync'] == true)
                    l10n.restaurantOpsIncidentPendingSync,
                  if (incident['_sync_needs_attention'] == true)
                    l10n.restaurantOpsIncidentNeedsAttention,
                ].whereType<String>().join(' · '),
              ),
              if (incident['is_blocking'] == true)
                Text(l10n.restaurantOpsIncidentBlocksWork),
              if (canManage)
                _IncidentManagerControls(
                  key: ValueKey(incident['id']),
                  incident: incident,
                  members: members,
                  busy: _saving ||
                      incident['_pending_sync'] == true ||
                      incident['_sync_needs_attention'] == true,
                  onSave: (status, assignedTo, blocking, note) => _run(
                    () => ref
                        .read(restaurantOpsRepositoryProvider)
                        .updateIncident(
                          branchId: widget.branchId,
                          incidentId: incident['id'] as String,
                          status: status,
                          assignedTo: assignedTo,
                          isBlocking: blocking,
                          note: note,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (pendingIncidents.isNotEmpty) ...[
        _SectionTitle(title: l10n.restaurantOpsSavedIncidentsTitle),
        ...pendingIncidents.map((incident) {
          final area = areas.where((item) => item['id'] == incident['area_id']);
          final areaName = area.isEmpty ? null : area.first['name'] as String?;
          return _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incident['description'] as String? ??
                      l10n.restaurantOpsIncidentFallback,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  [
                    if (areaName != null) areaName,
                    _incidentUrgencyLabel(
                      incident['urgency'] as String? ?? 'normal',
                      l10n,
                    ),
                    incident['needs_attention'] == true
                        ? l10n.restaurantOpsIncidentNeedsAttention
                        : l10n.restaurantOpsIncidentPendingSync,
                  ].whereType<String>().join(' · '),
                ),
                if (incident['is_blocking'] == true)
                  Text(l10n.restaurantOpsIncidentBlockingUnconfirmed),
              ],
            ),
          );
        }),
      ],
    ];
  }

  List<Widget> _handoffContent(
    String? userId,
    Map<String, bool> pendingAcknowledgements,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final handoff = widget.data['handoff'] as Map<String, dynamic>? ?? {};
    final complete = _maps(handoff['completed_tasks']);
    final open = _maps(handoff['outstanding_tasks']);
    final incidents = _maps(handoff['open_incidents']);
    final members = _maps(
      widget.data['members'],
    ).where((member) => member['user_id'] != userId).toList(growable: false);
    final recipientIsAvailable = members.any(
      (member) => member['user_id'] == _handoffRecipientId,
    );
    final selectedRecipient = recipientIsAvailable
        ? _handoffRecipientId ?? ''
        : '';
    final handoffs = _maps(widget.data['handoffs']);
    return [
      _InfoCard(text: l10n.restaurantOpsHandoffSummary),
      _SectionTitle(
        title: l10n.restaurantOpsHandoffCompletedCount(complete.length),
      ),
      if (complete.isEmpty)
        _InfoCard(text: l10n.restaurantOpsHandoffNoCompleted),
      ...complete.map(
        (task) => _simpleTask(task, l10n.restaurantCalendarStatusCompleted),
      ),
      _SectionTitle(
        title: l10n.restaurantOpsHandoffOutstandingCount(open.length),
      ),
      if (open.isEmpty) _InfoCard(text: l10n.restaurantOpsHandoffNoOutstanding),
      ...open.map(
        (task) => _simpleTask(
          task,
          _statusLabel(task['status'] as String? ?? 'pending', l10n),
        ),
      ),
      _SectionTitle(
        title: l10n.restaurantOpsHandoffIncidentCount(incidents.length),
      ),
      if (incidents.isEmpty) _InfoCard(text: l10n.restaurantOpsNoOpenIncidents),
      ...incidents.map(
        (incident) => _simpleTask(
          incident,
          _incidentUrgencyLabel(
            incident['urgency'] as String? ?? 'normal',
            l10n,
          ),
        ),
      ),
      _SectionTitle(title: l10n.restaurantOpsHandoffDeliveryTitle),
      _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.restaurantOpsHandoffSnapshotNote),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedRecipient,
              decoration: InputDecoration(
                labelText: l10n.restaurantOpsHandoffRecipient,
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n.restaurantOpsHandoffNoRecipient),
                ),
                ...members.map(
                  (member) => DropdownMenuItem(
                    value: member['user_id'] as String,
                    child: Text(
                      member['user_name'] as String? ??
                          l10n.restaurantOpsHandoffMemberFallback,
                    ),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _handoffRecipientId = value?.isEmpty == true
                          ? null
                          : value;
                      _handoffClientEventId = null;
                    }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _handoffNoteController,
              onChanged: (_) {
                _handoffClientEventId = null;
              },
              maxLength: 1000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.restaurantOpsHandoffNote,
                hintText: l10n.restaurantOpsHandoffNoteHint,
                alignLabelWithHint: true,
              ),
            ),
            _ActionButton(
              label: _saving
                  ? l10n.restaurantOpsSaving
                  : l10n.restaurantOpsHandoffDeliver,
              onPressed: _saving
                  ? null
                  : () => _deliverHandoff(
                      selectedRecipient.isEmpty ? null : selectedRecipient,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.restaurantOpsHandoffConnectionRequired,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      _SectionTitle(title: l10n.restaurantOpsRecentHandoffs(handoffs.length)),
      if (handoffs.isEmpty) _InfoCard(text: l10n.restaurantOpsNoHandoffs),
      ...handoffs.map((item) {
        final acknowledged = item['acknowledged_at'] != null;
        final pendingAckAttention = pendingAcknowledgements[item['id']];
        final addressedToMe = item['recipient_id'] == userId;
        final unassignedReceiver =
            item['recipient_id'] == null && item['created_by'] != userId;
        final canAcknowledge =
            !acknowledged &&
            pendingAckAttention == null &&
            (addressedToMe || unassignedReceiver);
        final deliveredAt = item['delivered_at'] as String? ?? '';
        final deliveredDate = deliveredAt.isEmpty
            ? null
            : DateTime.tryParse(deliveredAt)?.toLocal();
        final date = deliveredDate == null
            ? ''
            : '${MaterialLocalizations.of(context).formatMediumDate(deliveredDate)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(deliveredDate))}';
        final snapshot = item['snapshot'] as Map<String, dynamic>? ?? {};
        final snapshotTasks = _maps(snapshot['task_items']);
        final snapshotIncidents = _maps(snapshot['incident_items']);
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['creator_name'] ?? l10n.restaurantOpsTeamFallback} · ${_formatOpsDate(context, item['shift_date'] as String?)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                acknowledged
                    ? l10n.restaurantOpsHandoffReceivedBy(
                        item['acknowledged_by_name'] as String? ??
                            l10n.restaurantOpsTeamFallback,
                      )
                    : item['recipient_name'] == null
                    ? l10n.restaurantOpsHandoffPendingTeam
                    : l10n.restaurantOpsHandoffPendingRecipient(
                        item['recipient_name'] as String,
                      ),
              ),
              if (pendingAckAttention != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    pendingAckAttention
                        ? l10n.restaurantOpsHandoffAckNeedsAttention
                        : l10n.restaurantOpsHandoffAckPendingSync,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                l10n.restaurantOpsHandoffSnapshotSummary(
                  snapshotTasks.length,
                  snapshotIncidents.length,
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ...snapshotTasks
                  .take(4)
                  .map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ${task['name'] ?? l10n.restaurantCalendarFallbackActivity} · ${_statusLabel(task['status'] as String? ?? 'pending', l10n)}',
                          ),
                          if (task['latest_pause_note'] is String)
                            Text(
                              l10n.restaurantOpsHandoffPausePrefix(
                                task['latest_pause_note'] as String,
                              ),
                            ),
                          ..._maps(task['parts'])
                              .where(
                                (part) => part['latest_pause_note'] is String,
                              )
                              .map(
                                (part) => Text(
                                  '  ${part['zone_name'] ?? l10n.restaurantOpsZoneFallback} · ${l10n.restaurantOpsHandoffPausePrefix(part['latest_pause_note'] as String)}',
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
              ...snapshotIncidents
                  .take(4)
                  .map(
                    (incident) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        l10n.restaurantOpsHandoffIncidentDescription(
                          incident['description'] as String? ??
                              l10n.restaurantOpsNoDescription,
                        ),
                      ),
                    ),
                  ),
              if (item['handoff_note'] is String &&
                  (item['handoff_note'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item['handoff_note'] as String),
              ],
              if (date.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(date, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (canAcknowledge) ...[
                const SizedBox(height: 10),
                _ActionButton(
                  label: _saving
                      ? l10n.restaurantOpsSaving
                      : l10n.restaurantOpsHandoffConfirmReceipt,
                  onPressed: _saving
                      ? null
                      : () => _run(
                          () => ref
                              .read(restaurantOpsRepositoryProvider)
                              .acknowledgeHandoff(
                                branchId: widget.branchId,
                                handoffId: item['id'] as String,
                              ),
                        ),
                ),
              ],
            ],
          ),
        );
      }),
    ];
  }

  Widget _simpleTask(Map<String, dynamic> item, String status) => _SectionCard(
    child: Row(
      children: [
        Expanded(
          child: Text(
            item['name'] as String? ??
                item['description'] as String? ??
                'Actividad',
          ),
        ),
        const SizedBox(width: 12),
        Text(status),
      ],
    ),
  );
}

class _IncidentManagerControls extends StatefulWidget {
  const _IncidentManagerControls({
    super.key,
    required this.incident,
    required this.members,
    required this.busy,
    required this.onSave,
  });

  final Map<String, dynamic> incident;
  final List<Map<String, dynamic>> members;
  final bool busy;
  final Future<void> Function(
    String status,
    String? assignedTo,
    bool isBlocking,
    String? note,
  )
  onSave;

  @override
  State<_IncidentManagerControls> createState() =>
      _IncidentManagerControlsState();
}

class _IncidentManagerControlsState extends State<_IncidentManagerControls> {
  late String _status;
  late String _assignedTo;
  late bool _isBlocking;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadIncident();
  }

  @override
  void didUpdateWidget(covariant _IncidentManagerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incident['status'] != widget.incident['status'] ||
        oldWidget.incident['assigned_to'] != widget.incident['assigned_to'] ||
        oldWidget.incident['is_blocking'] != widget.incident['is_blocking']) {
      _loadIncident();
    }
  }

  void _loadIncident() {
    _status = widget.incident['status'] as String? ?? 'open';
    _assignedTo = widget.incident['assigned_to'] as String? ?? '';
    _isBlocking = widget.incident['is_blocking'] == true;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final assigneeMissing =
        _assignedTo.isNotEmpty &&
        !widget.members.any((member) => member['user_id'] == _assignedTo);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(l10n.restaurantOpsIncidentFollowupTitle),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: InputDecoration(
              labelText: l10n.restaurantOpsIncidentStatusLabel,
            ),
            items: [
              DropdownMenuItem(
                value: 'open',
                child: Text(l10n.restaurantOpsIncidentStatusOpen),
              ),
              DropdownMenuItem(
                value: 'in_progress',
                child: Text(l10n.restaurantOpsIncidentStatusInProgress),
              ),
              DropdownMenuItem(
                value: 'resolved',
                child: Text(l10n.restaurantOpsIncidentStatusResolved),
              ),
            ],
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _status = value ?? 'open'),
          ),
          DropdownButtonFormField<String>(
            value: _assignedTo,
            decoration: InputDecoration(
              labelText: l10n.restaurantCalendarAssignee,
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(l10n.restaurantCalendarNoAssignee),
              ),
              if (assigneeMissing)
                DropdownMenuItem(
                  value: _assignedTo,
                  enabled: false,
                  child: Text(
                    l10n.restaurantCalendarInactiveAssignee(
                      widget.incident['assignee_name'] as String? ??
                          l10n.restaurantCalendarFallbackAssignee,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ...widget.members.map(
                (member) => DropdownMenuItem(
                  value: member['user_id'] as String,
                  child: Text(
                    member['user_name'] as String? ??
                        member['user_id'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _assignedTo = value ?? ''),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.restaurantOpsIncidentBlocksWork),
            value: _isBlocking,
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _isBlocking = value),
          ),
          TextField(
            controller: _noteController,
            maxLength: 500,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.restaurantOpsIncidentFollowupNote,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: widget.busy
                  ? null
                  : () => widget.onSave(
                      _status,
                      _assignedTo.isEmpty ? null : _assignedTo,
                      _isBlocking,
                      _noteController.text,
                    ),
              icon: widget.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.restaurantOpsIncidentSaveFollowup),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchNotConfigured extends ConsumerStatefulWidget {
  const _BranchNotConfigured();

  @override
  ConsumerState<_BranchNotConfigured> createState() =>
      _BranchNotConfiguredState();
}

class _BranchNotConfiguredState extends ConsumerState<_BranchNotConfigured> {
  final _name = TextEditingController();
  String? _timezone;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Pollo Móvil')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                l10n.restaurantOpsBranchNotConfiguredTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(l10n.restaurantOpsBranchNotConfiguredMessage),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.restaurantOpsBranchName,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _timezone,
                decoration: InputDecoration(
                  labelText: l10n.restaurantOpsBranchTimeZone,
                ),
                items: _mexicoTimeZones.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _timezone = value),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed:
                      _saving ||
                          _name.text.trim().length < 2 ||
                          _timezone == null
                      ? null
                      : () async {
                          setState(() {
                            _saving = true;
                            _error = null;
                          });
                          try {
                            await ref
                                .read(restaurantOpsRepositoryProvider)
                                .createBranch(
                                  name: _name.text.trim(),
                                  timezone: _timezone!,
                                );
                            ref.invalidate(restaurantBranchesProvider);
                          } on Object catch (error) {
                            if (mounted)
                              setState(() => _error = error.toString());
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  child: Text(
                    _saving
                        ? l10n.restaurantOpsBranchCreating
                        : l10n.restaurantOpsBranchCreate,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _mexicoTimeZones = <String, String>{
  'America/Bahia_Banderas': 'Bahía de Banderas',
  'America/Cancun': 'Cancún',
  'America/Chihuahua': 'Chihuahua',
  'America/Ciudad_Juarez': 'Ciudad Juárez',
  'America/Hermosillo': 'Hermosillo',
  'America/Matamoros': 'Matamoros',
  'America/Mazatlan': 'Mazatlán',
  'America/Merida': 'Mérida',
  'America/Mexico_City': 'Ciudad de México',
  'America/Monterrey': 'Monterrey',
  'America/Ojinaga': 'Ojinaga',
  'America/Tijuana': 'Tijuana',
};

class _OpsLoading extends StatelessWidget {
  const _OpsLoading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _OpsMessage extends StatelessWidget {
  const _OpsMessage({
    required this.title,
    required this.message,
    required this.onRetry,
  });
  final String title;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Pollo Móvil')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: Text(l10n.restaurantCalendarRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => _SectionCard(child: Text(text));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton(onPressed: onPressed, child: Text(label)),
  );
}

String _dateOffset(String value, int days) {
  final date = DateTime.tryParse('${value}T00:00:00Z');
  if (date == null) return '';
  final shifted = date.add(Duration(days: days));
  return '${shifted.year.toString().padLeft(4, '0')}-${shifted.month.toString().padLeft(2, '0')}-${shifted.day.toString().padLeft(2, '0')}';
}

String _formatOpsDate(BuildContext context, String? value) {
  final parsed = DateTime.tryParse(value ?? '');
  if (parsed == null) return value ?? '';
  return MaterialLocalizations.of(
    context,
  ).formatMediumDate(DateTime(parsed.year, parsed.month, parsed.day));
}

List<Map<String, dynamic>> _maps(dynamic input) =>
    (input as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

String _statusLabel(String status, AppLocalizations l10n) => switch (status) {
  'pending' => l10n.restaurantCalendarStatusPending,
  'in_progress' => l10n.restaurantCalendarStatusInProgress,
  'paused' => l10n.restaurantCalendarStatusPaused,
  'blocked' => l10n.restaurantCalendarStatusBlocked,
  'completed' => l10n.restaurantCalendarStatusCompleted,
  _ => status,
};

String _absenceStatus(String status, AppLocalizations l10n) => switch (status) {
  'pending' => l10n.restaurantCalendarStatusPending,
  'approved' => l10n.restaurantAbsenceApproved,
  'denied' => l10n.restaurantOpsAbsenceStatusDenied,
  _ => status,
};

String _incidentUrgencyLabel(String urgency, AppLocalizations l10n) =>
    switch (urgency) {
      'low' => l10n.restaurantOpsUrgencyLow,
      'high' => l10n.restaurantOpsUrgencyHigh,
      'urgent' => l10n.restaurantOpsUrgencyUrgent,
      _ => l10n.restaurantOpsUrgencyNormal,
    };

String _incidentStatusLabel(String status, AppLocalizations l10n) =>
    switch (status) {
      'in_progress' => l10n.restaurantOpsIncidentStatusInProgress,
      'resolved' => l10n.restaurantOpsIncidentStatusResolved,
      _ => l10n.restaurantOpsIncidentStatusOpen,
    };

String _isoDate(DateTime date) => date.toIso8601String().substring(0, 10);

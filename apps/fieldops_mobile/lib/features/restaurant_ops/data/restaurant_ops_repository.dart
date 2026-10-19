import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/camera/data/exif_stripper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef OpsJson = Map<String, dynamic>;

class RestaurantOpsRepository {
  RestaurantOpsRepository(this._client, this._database, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final LocalDatabase _database;
  final Uuid _uuid;

  Future<bool> _isDefinitelyOffline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return connectivity.contains(ConnectivityResult.none);
    } on Object {
      // Connectivity plugins can be unavailable on simulators or after a
      // platform-channel failure. In that case, attempt the request and let
      // the transport decide whether it needs to be queued.
      return false;
    }
  }

  Future<List<OpsJson>> fetchBranches() async {
    final data = await _fetchWithSnapshot(
      _snapshotKey('branches'),
      () => _invoke('GET', query: {'action': 'branches'}),
    );
    return (data['branches'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<OpsJson> fetchDashboard(String branchId) => _fetchWithSnapshot(
        _snapshotKey('dashboard:$branchId'),
        () => _invoke(
          'GET',
          query: {'action': 'dashboard', 'branch_id': branchId},
        ),
      );

  Future<OpsJson> fetchAttendanceHistory(String branchId, String forDate) =>
      _fetchWithSnapshot(
        _snapshotKey('attendance-history:$branchId:$forDate'),
        () => _invoke(
          'GET',
          query: {
            'action': 'attendance_history',
            'branch_id': branchId,
            'for_date': forDate,
          },
        ),
      );

  Future<OpsJson> fetchPendingAbsences(String branchId) => _fetchWithSnapshot(
        _snapshotKey('pending-absences:$branchId'),
        () => _invoke(
          'GET',
          query: {'action': 'pending_absences', 'branch_id': branchId},
        ),
      );

  Future<OpsJson> fetchShiftSchedule(String branchId, String weekStart) =>
      _fetchWithSnapshot(
        _snapshotKey('shift-schedule:$branchId:$weekStart'),
        () => _invoke(
          'GET',
          query: {
            'action': 'shift_schedule',
            'branch_id': branchId,
            'week_start': weekStart,
          },
        ),
      );

  Future<OpsJson> fetchShiftCoverRequests(String branchId) =>
      _fetchWithSnapshot(
        _snapshotKey('shift-cover-requests:$branchId'),
        () => _invoke(
          'GET',
          query: {'action': 'shift_cover_requests', 'branch_id': branchId},
        ),
      );

  Future<OpsJson> fetchTeamDirectory(String branchId) => _fetchWithSnapshot(
        _snapshotKey('team-directory:$branchId'),
        () => _invoke(
          'GET',
          query: {'action': 'team_directory', 'branch_id': branchId},
        ),
      );

  Future<OpsJson> fetchBranchStructure(String branchId) => _fetchWithSnapshot(
        _snapshotKey('branch-structure:$branchId'),
        () => _invoke(
          'GET',
          query: {'action': 'branch_structure', 'branch_id': branchId},
        ),
      );

  Future<OpsJson> saveBranchArea({
    required String branchId,
    String? areaId,
    required String name,
    required bool isActive,
  }) =>
      _invoke('POST', body: {
        'action': 'save_area',
        'branch_id': branchId,
        if (areaId != null) 'id': areaId,
        'name': name,
        'is_active': isActive,
      });

  Future<OpsJson> saveBranchPosition({
    required String branchId,
    String? positionId,
    required String name,
    required bool isActive,
  }) =>
      _invoke('POST', body: {
        'action': 'save_position',
        'branch_id': branchId,
        if (positionId != null) 'id': positionId,
        'name': name,
        'is_active': isActive,
      });

  Future<OpsJson> saveBranchFeatures({
    required String branchId,
    required bool enableTimeClock,
    required bool requireGps,
  }) =>
      _invoke('POST', body: {
        'action': 'save_branch_features',
        'branch_id': branchId,
        'enable_time_clock': enableTimeClock,
        'require_gps_for_time_clock': enableTimeClock && requireGps,
      });

  Future<OpsJson> saveMemberRole({
    required String branchId,
    required String userId,
    required String accessRole,
  }) =>
      _invoke('POST', body: {
        'action': 'save_member',
        'branch_id': branchId,
        'user_id': userId,
        'access_role': accessRole,
      });

  Future<OpsJson> setMemberActive({
    required String branchId,
    required String userId,
    required bool isActive,
  }) =>
      _invoke('POST', body: {
        'action': 'set_member_active',
        'branch_id': branchId,
        'user_id': userId,
        'is_active': isActive,
      });

  Future<OpsJson> inviteMember({
    required String branchId,
    required String fullName,
    required String email,
  }) =>
      _invoke('POST', body: {
        'action': 'invite_member',
        'branch_id': branchId,
        'full_name': fullName,
        'email': email,
      });

  Future<OpsJson> saveMemberPositions({
    required String branchId,
    required String userId,
    required List<String> positionIds,
  }) =>
      _invoke('POST', body: {
        'action': 'save_member_positions',
        'branch_id': branchId,
        'user_id': userId,
        'position_ids': positionIds,
      });

  Future<OpsJson> reviewAbsence({
    required String branchId,
    required String absenceId,
    required String status,
  }) =>
      _invoke('POST', body: {
        'action': 'review_absence',
        'branch_id': branchId,
        'absence_id': absenceId,
        'status': status,
      });

  Future<OpsJson> saveShift({
    required String branchId,
    String? shiftId,
    required String employeeId,
    required String shiftDate,
    required String startTime,
    required String endTime,
    required String status,
    required List<OpsJson> breaks,
  }) =>
      _invoke('POST', body: {
        'action': 'save_shift',
        'branch_id': branchId,
        if (shiftId != null) 'shift_id': shiftId,
        'employee_id': employeeId,
        'shift_date': shiftDate,
        'start_time': startTime,
        'end_time': endTime,
        'status': status,
        'breaks': breaks,
      });

  Future<OpsJson> cancelShift({
    required String branchId,
    required String shiftId,
  }) =>
      _invoke('POST', body: {
        'action': 'cancel_shift',
        'branch_id': branchId,
        'shift_id': shiftId,
      });

  Future<OpsJson> requestShiftCover({
    required String branchId,
    required String shiftId,
    String? note,
  }) async {
    final clientEventId = _uuid.v4();
    final result = await _dispatchOrQueue(branchId, {
      'action': 'request_shift_cover',
      'branch_id': branchId,
      'shift_id': shiftId,
      'client_event_id': clientEventId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return {...result, 'client_event_id': clientEventId};
  }

  Future<OpsJson> cancelShiftCoverRequest({
    required String branchId,
    required String requestId,
  }) async {
    final clientEventId = _uuid.v4();
    final payload = <String, dynamic>{
      'action': 'cancel_shift_cover_request',
      'branch_id': branchId,
      'request_id': requestId,
      'client_event_id': clientEventId,
    };
    final actorId = _client.auth.currentUser?.id;
    final waitsForQueuedRequest = actorId != null &&
        await _database.hasUnresolvedRestaurantShiftCoverRequest(
          branchId: branchId,
          actorId: actorId,
          clientEventId: requestId,
        );
    final OpsJson result;
    if (waitsForQueuedRequest) {
      await _queue(branchId, payload);
      result = {'queued': true};
    } else {
      result = await _dispatchOrQueue(branchId, payload);
    }
    return {...result, 'client_event_id': clientEventId};
  }

  Future<OpsJson> reviewShiftCoverRequest({
    required String branchId,
    required String requestId,
    required String decision,
    String? replacementEmployeeId,
    String? decisionNote,
  }) =>
      _invoke('POST', body: {
        'action': 'review_shift_cover_request',
        'branch_id': branchId,
        'request_id': requestId,
        'decision': decision,
        if (replacementEmployeeId != null)
          'replacement_employee_id': replacementEmployeeId,
        if (decisionNote != null && decisionNote.trim().isNotEmpty)
          'decision_note': decisionNote.trim(),
      });

  Future<OpsJson> fetchTaskCalendar(
    String branchId, {
    required String fromDate,
    required String toDate,
  }) =>
      _fetchWithSnapshot(
        _snapshotKey('task-calendar:$branchId:$fromDate:$toDate'),
        () => _invoke(
          'GET',
          query: {
            'action': 'task_calendar',
            'branch_id': branchId,
            'from_date': fromDate,
            'to_date': toDate,
          },
        ),
      );

  Future<OpsJson> scheduleTasks(String branchId, String forDate) => _invoke(
        'POST',
        body: {
          'action': 'schedule_tasks',
          'branch_id': branchId,
          'for_date': forDate,
        },
      );

  Future<OpsJson> rescheduleTask(
    String branchId,
    String taskId,
    String scheduledFor,
  ) =>
      _invoke(
        'POST',
        body: {
          'action': 'reschedule_task',
          'branch_id': branchId,
          'task_id': taskId,
          'scheduled_for': scheduledFor,
        },
      );

  Future<OpsJson> assignTask(
    String branchId,
    String taskId,
    String? assignedTo,
  ) =>
      _invoke(
        'POST',
        body: {
          'action': 'assign_task',
          'branch_id': branchId,
          'task_id': taskId,
          'assigned_to': assignedTo,
        },
      );

  Future<OpsJson> assignTaskPart(
    String branchId,
    String taskId,
    String partId,
    String? assignedTo,
  ) =>
      _invoke(
        'POST',
        body: {
          'action': 'assign_task_part',
          'branch_id': branchId,
          'task_id': taskId,
          'part_id': partId,
          'assigned_to': assignedTo,
        },
      );

  Future<OpsJson> autoAssignTasks(String branchId, {String? forDate}) => _invoke(
        'POST',
        body: {
          'action': 'auto_assign',
          'branch_id': branchId,
          if (forDate != null) 'for_date': forDate,
        },
      );

  Future<OpsJson> fetchSettings(String branchId, {String? weekStart}) =>
      _fetchWithSnapshot(
        _snapshotKey('settings:$branchId:${weekStart ?? ''}'),
        () => _invoke(
          'GET',
          query: {
            'action': 'settings',
            'branch_id': branchId,
            if (weekStart != null) 'week_start': weekStart,
          },
        ),
      );

  Future<OpsJson> fetchNotifications(String branchId) => _fetchWithSnapshot(
        _snapshotKey('notifications:$branchId'),
        () => _invoke(
          'GET',
          query: {'action': 'notification_inbox', 'branch_id': branchId},
        ),
      );

  String? _snapshotKey(String scope) {
    final userId = _client.auth.currentUser?.id;
    return userId == null ? null : '$userId:$scope';
  }

  Future<String?> fetchSelectedBranchId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      return await _database.readRestaurantPreference(
        userId: userId,
        key: 'selected_branch_id',
      );
    } on Object {
      return null;
    }
  }

  Future<void> saveSelectedBranchId(String branchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _database.saveRestaurantPreference(
        userId: userId,
        key: 'selected_branch_id',
        value: branchId,
      );
    } on Object {
      // A local preference failure must not interrupt branch switching.
    }
  }

  Future<OpsJson> _fetchWithSnapshot(
    String? key,
    Future<OpsJson> Function() fetch,
  ) async {
    try {
      final value = await fetch();
      if (key != null) {
        try {
          await _database.saveRestaurantSnapshot(key, jsonEncode(value));
        } on Object {
          // A local cache failure must not hide a successful live response.
        }
      }
      return value;
    } on SocketException {
      final cached = key == null ? null : await _readSnapshot(key);
      if (cached != null) return cached;
      rethrow;
    } on TimeoutException {
      final cached = key == null ? null : await _readSnapshot(key);
      if (cached != null) return cached;
      rethrow;
    } on RestaurantOpsException catch (error) {
      final status = error.status;
      final transient = status == null || status == 0 || status >= 500 ||
          const {408, 425, 429}.contains(status);
      if (!transient) rethrow;
      final cached = key == null ? null : await _readSnapshot(key);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<OpsJson?> _readSnapshot(String key) async {
    try {
      final row = await _database.readRestaurantSnapshot(key);
      if (row == null) return null;
      final decoded = jsonDecode(row['payload']!);
      if (decoded is! Map<String, dynamic>) return null;
      return {
        ...decoded,
        '_offline_snapshot': true,
        '_snapshot_saved_at': row['updated_at'],
      };
    } on Object {
      return null;
    }
  }

  Future<OpsJson> markNotificationRead({
    required String branchId,
    required String notificationId,
  }) => _dispatchOrQueue(branchId, {
      'action': 'mark_notification_read',
      'branch_id': branchId,
      'notification_id': notificationId,
      'client_event_id': _uuid.v4(),
    });

  Future<OpsJson> markAllNotificationsRead(String branchId) =>
      _dispatchOrQueue(branchId, {
      'action': 'mark_all_notifications_read',
      'branch_id': branchId,
      'client_event_id': _uuid.v4(),
    });

  Future<OpsJson> deliverHandoff({
    required String branchId,
    required String clientEventId,
    String? recipientId,
    String note = '',
  }) =>
      _invoke('POST', body: {
        'action': 'deliver_handoff',
        'branch_id': branchId,
        'client_event_id': clientEventId,
        if (recipientId != null && recipientId.isNotEmpty)
          'recipient_id': recipientId,
        'handoff_note': note,
      });

  String createClientEventId() => _uuid.v4();

  Future<OpsJson> acknowledgeHandoff({
    required String branchId,
    required String handoffId,
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'acknowledge_handoff',
        'branch_id': branchId,
        'client_event_id': _uuid.v4(),
        'handoff_id': handoffId,
      });

  Future<OpsJson> requestAbsence({
    required String branchId,
    required String startDate,
    required String endDate,
    String? note,
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'request_absence',
        'branch_id': branchId,
        'client_event_id': _uuid.v4(),
        'start_date': startDate,
        'end_date': endDate,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<OpsJson> recordAreaInspection({
    required String branchId,
    required String templateId,
    required String clientEventId,
    required List<OpsJson> results,
    String note = '',
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'record_area_inspection',
        'branch_id': branchId,
        'template_id': templateId,
        'client_event_id': clientEventId,
        'results': results,
        'note': note,
      });

  Future<OpsJson> createBranch({
    required String name,
    required String timezone,
  }) =>
      _invoke('POST', body: {
        'action': 'create_branch',
        'name': name,
        'timezone': timezone,
      });

  Future<OpsJson> taskAction({
    required String branchId,
    required String taskId,
    String? partId,
    required String action,
    String? note,
    String? evidencePath,
  }) async {
    final payload = <String, dynamic>{
      'action': 'task_action',
      'branch_id': branchId,
      'task_id': taskId,
      'client_event_id': _uuid.v4(),
      'task_action': action,
      if (partId != null) 'part_id': partId,
      if (note != null) 'note': note,
      if (evidencePath != null) 'evidence_path': evidencePath,
    };
    return _dispatchOrQueue(branchId, payload);
  }

  Future<OpsJson> inspectWaste({
    required String branchId,
    required List<OpsJson> results,
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'inspect_waste',
        'branch_id': branchId,
        'client_event_id': _uuid.v4(),
        'results': results,
      });

  Future<OpsJson> createIncident({
    required String branchId,
    required String description,
    String? areaId,
    String urgency = 'normal',
    bool isBlocking = false,
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'create_incident',
        'branch_id': branchId,
        'client_event_id': _uuid.v4(),
        'description': description,
        if (areaId != null) 'area_id': areaId,
        'urgency': urgency,
        'is_blocking': isBlocking,
      });

  Future<OpsJson> updateIncident({
    required String branchId,
    required String incidentId,
    required String status,
    String? assignedTo,
    required bool isBlocking,
    String? note,
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'update_incident',
        'branch_id': branchId,
        'client_event_id': _uuid.v4(),
        'incident_id': incidentId,
        'status': status,
        'assigned_to': assignedTo,
        'is_blocking': isBlocking,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<String> uploadEvidence({
    required String branchId,
    required String taskId,
    String? partId,
    required String filePath,
  }) async {
    await ExifStripper().stripFile(filePath);
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const RestaurantOpsException('La foto debe pesar menos de 10 MB.');
    }
    final eventId = _uuid.v4();
    final objectPath = '$branchId/$taskId/$eventId.jpg';
    if (await _isDefinitelyOffline()) {
      await _queueEvidence(
        eventId: eventId, branchId: branchId, taskId: taskId, partId: partId,
        sourcePath: filePath, bytes: bytes, objectPath: objectPath,
      );
      return objectPath;
    }
    try {
      await _client.storage.from('restaurant-evidence').uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: false,
            ),
          );
      await _invoke('POST', body: {
        'action': 'register_evidence',
        'branch_id': branchId,
        'task_id': taskId,
        if (partId != null) 'part_id': partId,
        'object_path': objectPath,
        'mime_type': 'image/jpeg',
        'file_size_bytes': bytes.length,
      });
      await _deleteTemporaryCapture(filePath);
    } on SocketException {
      await _queueEvidence(
        eventId: eventId, branchId: branchId, taskId: taskId, partId: partId,
        sourcePath: filePath, bytes: bytes, objectPath: objectPath,
      );
    } on TimeoutException {
      await _queueEvidence(
        eventId: eventId, branchId: branchId, taskId: taskId, partId: partId,
        sourcePath: filePath, bytes: bytes, objectPath: objectPath,
      );
    } on StorageException catch (error) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status != null && status >= 400 && status < 500 &&
          !const {408, 425, 429}.contains(status)) {
        throw RestaurantOpsException(error.message, status: status);
      }
      await _queueEvidence(
        eventId: eventId, branchId: branchId, taskId: taskId, partId: partId,
        sourcePath: filePath, bytes: bytes, objectPath: objectPath,
      );
    } on RestaurantOpsException catch (error) {
      final status = error.status;
      if (status != null && status >= 400 && status < 500 &&
          !const {408, 425, 429}.contains(status)) rethrow;
      await _queueEvidence(
        eventId: eventId, branchId: branchId, taskId: taskId, partId: partId,
        sourcePath: filePath, bytes: bytes, objectPath: objectPath,
      );
    }
    return objectPath;
  }

  Future<void> _queueEvidence({
    required String eventId,
    required String branchId,
    required String taskId,
    required String? partId,
    required String sourcePath,
    required Uint8List bytes,
    required String objectPath,
  }) async {
    final actorId = _client.auth.currentUser?.id;
    if (actorId == null) {
      throw const RestaurantOpsException('Inicia sesión antes de guardar evidencia sin conexión.');
    }
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory('${documents.path}/pollo_movil_evidence/$branchId/$taskId');
    await folder.create(recursive: true);
    final durableFile = File('${folder.path}/$eventId.jpg');
    await durableFile.writeAsBytes(bytes, flush: true);
    final payload = <String, dynamic>{
      'action': 'upload_evidence',
      'branch_id': branchId,
      'task_id': taskId,
      if (partId != null) 'part_id': partId,
      'client_event_id': eventId,
      'queued_by_user_id': actorId,
      'file_path': durableFile.path,
      'object_path': objectPath,
      'mime_type': 'image/jpeg',
      'file_size_bytes': bytes.length,
    };
    try {
      await _database.into(_database.pendingEvents).insert(
            PendingEventsCompanion.insert(
              id: eventId,
              eventType: 'restaurant_ops',
              jobId: branchId,
              payload: jsonEncode(payload),
              occurredAt: DateTime.now().toUtc(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } on Object {
      if (await durableFile.exists()) await durableFile.delete();
      throw const RestaurantOpsException(
        'El almacenamiento seguro no está disponible; la evidencia no pudo guardarse sin conexión.',
      );
    }
    await _deleteTemporaryCapture(sourcePath);
  }

  Future<void> _deleteTemporaryCapture(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A confirmed upload or durable outbox copy is already safe to retry.
    }
  }

  Future<void> setCustomerService({
    required String branchId,
    required bool active,
  }) async {
    await _invoke('POST', body: {
      'action': 'set_customer_service',
      'branch_id': branchId,
      'active': active,
    });
  }

  Future<OpsJson> recordTimeEvent({
    required String branchId,
    required String eventType,
    required DateTime occurredAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) =>
      _dispatchOrQueue(branchId, {
        'action': 'record_time_event',
        'branch_id': branchId,
        'client_event_id': _uuid.v4(),
        'event_type': eventType,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_m': accuracyMeters,
      });

  Future<OpsJson?> pendingClockState(String branchId) async {
    final actorId = _client.auth.currentUser?.id;
    if (actorId == null) return null;
    return _database.latestOutstandingRestaurantClockState(
      branchId: branchId,
      actorId: actorId,
    );
  }

  Stream<List<PendingEvent>> watchOutstandingRestaurantEvents(String branchId) =>
      _database.watchOutstandingRestaurantEvents(branchId);

  Future<OpsJson> _dispatchOrQueue(String branchId, OpsJson payload) async {
    final evidencePath = payload['evidence_path'];
    final actorId = _client.auth.currentUser?.id;
    if (payload['action'] == 'record_time_event' &&
        actorId != null &&
        await _database.hasOutstandingRestaurantClockEvent(
          branchId: branchId,
          actorId: actorId,
        )) {
      await _queue(branchId, payload);
      return {'queued': true};
    }
    if (evidencePath is String &&
        await _database.hasOutstandingRestaurantEvidence(evidencePath)) {
      await _queue(branchId, payload);
      return {'queued': true};
    }
    if (await _isDefinitelyOffline()) {
      await _queue(branchId, payload);
      return {'queued': true};
    }
    try {
      return await _invoke('POST', body: payload);
    } on SocketException {
      await _queue(branchId, payload);
      return {'queued': true};
    } on TimeoutException {
      await _queue(branchId, payload);
      return {'queued': true};
    } on RestaurantOpsException catch (error) {
      final status = error.status;
      if (status != null && (status >= 500 || const {408, 425, 429}.contains(status))) {
        await _queue(branchId, payload);
        return {'queued': true};
      }
      rethrow;
    }
  }

  Future<void> _queue(String branchId, OpsJson payload) async {
    final eventId = payload['client_event_id'] as String;
    final actorId = _client.auth.currentUser?.id;
    if (actorId == null) {
      throw const RestaurantOpsException('Inicia sesión antes de guardar cambios sin conexión.');
    }
    final durablePayload = <String, dynamic>{
      ...payload,
      'queued_by_user_id': actorId,
    };
    try {
      await _database.into(_database.pendingEvents).insert(
            PendingEventsCompanion.insert(
              id: eventId,
              eventType: 'restaurant_ops',
              jobId: branchId,
              payload: jsonEncode(durablePayload),
              occurredAt: DateTime.now().toUtc(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } on Object {
      throw const RestaurantOpsException(
        'El almacenamiento seguro no está disponible; el cambio no pudo guardarse sin conexión.',
      );
    }
  }

  Future<OpsJson> _invoke(
    String method, {
    Map<String, String>? query,
    OpsJson? body,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'restaurant_ops',
        method: method == 'GET' ? HttpMethod.get : HttpMethod.post,
        queryParameters: query,
        body: body,
        headers: const {'X-Client-Version': 'pollo-movil'},
      );
      if (response.data is! Map<String, dynamic>) {
        throw const RestaurantOpsException('La respuesta del servidor no es válida.');
      }
      return response.data as OpsJson;
    } on FunctionException catch (error) {
      if (error.status == 0) throw const SocketException('No hay conexión disponible.');
      final detail = error.details;
      final message = detail is Map<String, dynamic>
          ? detail['message']?.toString()
          : detail?.toString();
      throw RestaurantOpsException(
        message?.isNotEmpty == true ? message! : 'No se pudo guardar (${error.status}).',
        status: error.status,
      );
    }
  }
}

class RestaurantOpsException implements Exception {
  const RestaurantOpsException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

OpsJson projectPendingRestaurantTaskActions({
  required OpsJson dashboard,
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final rawTasks = dashboard['tasks'];
  if (rawTasks is! List || events.isEmpty) return dashboard;

  final tasks = <OpsJson>[];
  final tasksById = <String, OpsJson>{};
  for (final rawTask in rawTasks) {
    if (rawTask is! Map<String, dynamic>) continue;
    final task = Map<String, dynamic>.from(rawTask);
    final parts = <OpsJson>[];
    final rawParts = rawTask['parts'];
    if (rawParts is List) {
      for (final rawPart in rawParts) {
        if (rawPart is Map<String, dynamic>) {
          parts.add(Map<String, dynamic>.from(rawPart));
        }
      }
    }
    if (rawParts is List) task['parts'] = parts;
    tasks.add(task);
    final id = task['id'];
    if (id is String) tasksById[id] = task;
  }

  final payloads = <PendingEvent, OpsJson>{};
  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is Map<String, dynamic>) payloads[event] = decoded;
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }

  final outstandingEvidence = <String>{};
  for (final event in events) {
    final payload = payloads[event];
    final objectPath = payload?['object_path'];
    if (payload?['action'] == 'upload_evidence' && objectPath is String) {
      outstandingEvidence.add(objectPath);
    }
  }

  final blockedUnits = <String>{};
  for (final event in events) {
    final payload = payloads[event];
    if (payload == null ||
        payload['queued_by_user_id'] != actorId ||
        payload['branch_id'] != branchId ||
        payload['action'] != 'task_action') {
      continue;
    }

    final taskId = payload['task_id'];
    if (taskId is! String) continue;
    final partId = payload['part_id'];
    final unitKey = '$taskId:${partId is String ? partId : 'task'}';
    if (event.syncStatus != 'pending') {
      blockedUnits.add(unitKey);
      continue;
    }
    if (blockedUnits.contains(unitKey)) continue;

    final task = tasksById[taskId];
    if (task == null) {
      blockedUnits.add(unitKey);
      continue;
    }

    OpsJson target = task;
    if (partId is String) {
      final parts = task['parts'];
      if (parts is! List) {
        blockedUnits.add(unitKey);
        continue;
      }
      final matchingParts = parts.whereType<Map<String, dynamic>>().where(
            (part) => part['id'] == partId,
          );
      if (matchingParts.isEmpty) {
        blockedUnits.add(unitKey);
        continue;
      }
      target = matchingParts.first;
    }

    final assignedTo = target['assigned_to'];
    final status = target['status'] as String? ?? 'pending';
    final action = payload['task_action'];
    var accepted = true;

    if (action == 'claim') {
      if (assignedTo != null && assignedTo != actorId) {
        accepted = false;
      } else {
        target['assigned_to'] = actorId;
      }
    } else if (action == 'start') {
      if (assignedTo != null && assignedTo != actorId) {
        accepted = false;
      } else {
        target['assigned_to'] = actorId;
        if (status != 'completed') target['status'] = 'in_progress';
      }
    } else if (action == 'pause') {
      if (assignedTo != null && assignedTo != actorId) {
        accepted = false;
      } else {
        target['assigned_to'] = actorId;
        if (status != 'completed') target['status'] = 'paused';
        final note = payload['note'];
        if (note is String && note.trim().isNotEmpty) {
          target['latest_pause_note'] = note;
        }
      }
    } else if (action == 'resume') {
      if (assignedTo != null && assignedTo != actorId) {
        accepted = false;
      } else {
        target['assigned_to'] = actorId;
        if (status != 'completed') target['status'] = 'in_progress';
      }
    } else if (action == 'complete' || action == 'bag_changed') {
      final isWasteTask = task['task_source'] == 'waste';
      final evidencePath = payload['evidence_path'];
      if ((assignedTo != null && assignedTo != actorId) ||
          (action == 'bag_changed' && !isWasteTask) ||
          (task['requires_evidence'] == true &&
              (evidencePath is! String || outstandingEvidence.contains(evidencePath)))) {
        accepted = false;
      } else {
        target['assigned_to'] = actorId;
        target['status'] = 'completed';
      }
    } else if (action == 'block') {
      if (assignedTo != null && assignedTo != actorId) {
        accepted = false;
      } else {
        target['assigned_to'] = actorId;
        if (status != 'completed') target['status'] = 'blocked';
      }
    } else {
      accepted = false;
    }

    if (!accepted) {
      blockedUnits.add(unitKey);
      continue;
    }

    target['_pending_sync'] = true;
    if (partId is String) {
      final parts = task['parts'] as List<dynamic>;
      final allCompleted = parts.isNotEmpty && parts.every(
        (part) => part is Map<String, dynamic> && part['status'] == 'completed',
      );
      if (allCompleted) {
        task['status'] = 'completed';
      } else if (action != 'claim' && task['status'] == 'pending') {
        task['status'] = 'in_progress';
      }
    }
  }

  return {...dashboard, 'tasks': tasks};
}

OpsJson? pendingRestaurantWasteInspection({
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final matching = <PendingEvent>[];
  final payloads = <PendingEvent, OpsJson>{};
  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId ||
          decoded['action'] != 'inspect_waste') {
        continue;
      }
      payloads[event] = decoded;
      matching.add(event);
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }
  if (matching.isEmpty) return null;

  final latest = matching.last;
  final results = payloads[latest]?['results'];
  final states = <String, String>{};
  if (results is List) {
    for (final result in results) {
      if (result is! Map<String, dynamic>) continue;
      final binId = result['bin_id'];
      final state = result['state'];
      if (binId is String && state is String &&
          const {'low', 'half', 'full'}.contains(state)) {
        states[binId] = state;
      }
    }
  }
  return {
    'states': states,
    'needs_attention': matching.any((event) => event.syncStatus != 'pending'),
  };
}

Map<String, OpsJson> pendingRestaurantAreaInspections({
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final inspections = <String, OpsJson>{};
  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId ||
          decoded['action'] != 'record_area_inspection') {
        continue;
      }
      final templateId = decoded['template_id'];
      if (templateId is! String || decoded['results'] is! List) continue;
      final previous = inspections[templateId];
      inspections[templateId] = {
        'results': decoded['results'],
        'note': decoded['note'],
        'needs_attention': event.syncStatus != 'pending' ||
            previous?['needs_attention'] == true,
      };
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }
  return inspections;
}

List<OpsJson> pendingRestaurantIncidents({
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final incidents = <OpsJson>[];
  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId ||
          decoded['action'] != 'create_incident') {
        continue;
      }
      incidents.add({
        'client_event_id': decoded['client_event_id'] ?? event.id,
        'description': decoded['description'],
        'area_id': decoded['area_id'],
        'urgency': decoded['urgency'],
        'is_blocking': decoded['is_blocking'] == true,
        'needs_attention': event.syncStatus != 'pending',
      });
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }
  return incidents;
}

OpsJson projectPendingRestaurantIncidentUpdates({
  required OpsJson dashboard,
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final rawIncidents = dashboard['incidents'];
  if (rawIncidents is! List || events.isEmpty) return dashboard;

  final incidents = rawIncidents
      .whereType<Map<String, dynamic>>()
      .map((incident) => Map<String, dynamic>.from(incident))
      .toList(growable: false);
  final incidentsById = <String, OpsJson>{
    for (final incident in incidents)
      if (incident['id'] is String) incident['id'] as String: incident,
  };
  final pendingEvents = <PendingEvent>[];
  final payloads = <PendingEvent, OpsJson>{};
  final attentionIncidentIds = <String>{};

  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId ||
          decoded['action'] != 'update_incident') {
        continue;
      }
      final incidentId = decoded['incident_id'];
      if (incidentId is! String || !incidentsById.containsKey(incidentId)) {
        continue;
      }
      if (event.syncStatus == 'pending') {
        pendingEvents.add(event);
        payloads[event] = decoded;
      } else {
        attentionIncidentIds.add(incidentId);
      }
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }

  pendingEvents.sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
  final members = (dashboard['members'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  for (final incidentId in attentionIncidentIds) {
    final incident = incidentsById[incidentId];
    if (incident != null) incident['_sync_needs_attention'] = true;
  }
  for (final event in pendingEvents) {
    final payload = payloads[event]!;
    final incidentId = payload['incident_id'] as String;
    if (attentionIncidentIds.contains(incidentId)) continue;
    final incident = incidentsById[incidentId]!;
    final assigneeId = payload['assigned_to'] as String?;
    String? assigneeName;
    if (assigneeId != null) {
      for (final member in members) {
        if (member['user_id'] == assigneeId) {
          assigneeName = member['user_name'] as String?;
          break;
        }
      }
    }
    incident['status'] = payload['status'];
    incident['assigned_to'] = assigneeId;
    incident['assignee_name'] = assigneeName;
    incident['is_blocking'] = payload['is_blocking'] == true;
    incident['_pending_sync'] = true;
  }

  return {...dashboard, 'incidents': incidents};
}

Map<String, bool> pendingRestaurantHandoffAcknowledgements({
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final handoffs = <String, bool>{};
  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId ||
          decoded['action'] != 'acknowledge_handoff') {
        continue;
      }
      final handoffId = decoded['handoff_id'];
      if (handoffId is String) {
        handoffs[handoffId] = event.syncStatus != 'pending';
      }
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }
  return handoffs;
}

List<OpsJson> pendingRestaurantAbsenceRequests({
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final requests = <OpsJson>[];
  for (final event in events) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId ||
          decoded['action'] != 'request_absence') {
        continue;
      }
      requests.add({
        'client_event_id': decoded['client_event_id'] ?? event.id,
        'start_date': decoded['start_date'],
        'end_date': decoded['end_date'],
        'note': decoded['note'],
        'needs_attention': event.syncStatus != 'pending',
      });
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }
  return requests;
}

List<OpsJson> pendingRestaurantShiftCoverRequests({
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final requestsById = <String, OpsJson>{};
  final cancellationEvents = <MapEntry<PendingEvent, Map<String, dynamic>>>[];
  final orderedEvents = [...events]
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  for (final event in orderedEvents) {
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId) {
        continue;
      }
      if (decoded['action'] == 'request_shift_cover') {
        final requestId = decoded['client_event_id'] is String
            ? decoded['client_event_id'] as String
            : event.id;
        requestsById[requestId] = {
          'id': requestId,
          'client_event_id': requestId,
          'shift_id': decoded['shift_id'],
          'requester_id': actorId,
          'requester_name': null,
          'status': event.syncStatus == 'pending' ? 'pending_sync' : 'sync_attention',
          'note': decoded['note'],
          'shift': null,
          'replacement_shift': null,
          'replacement_employee_name': null,
          'decision_note': null,
          '_local_outbox': true,
          'needs_attention': event.syncStatus != 'pending',
        };
      } else if (decoded['action'] == 'cancel_shift_cover_request' &&
          decoded['request_id'] is String) {
        cancellationEvents.add(MapEntry(event, decoded));
      }
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }
  for (final cancellation in cancellationEvents) {
    final event = cancellation.key;
    final requestId = cancellation.value['request_id'] as String;
    final existing = requestsById[requestId];
    final needsAttention = existing?['needs_attention'] == true ||
        event.syncStatus != 'pending';
    requestsById[requestId] = {
      ...?existing,
      'id': requestId,
      'client_event_id': existing?['client_event_id'] ?? requestId,
      'requester_id': actorId,
      'status': needsAttention ? 'sync_attention' : 'cancel_pending_sync',
      'shift': existing?['shift'],
      'replacement_shift': existing?['replacement_shift'],
      'replacement_employee_name': existing?['replacement_employee_name'],
      'decision_note': existing?['decision_note'],
      '_local_outbox': true,
      'needs_attention': needsAttention,
    };
  }
  return requestsById.values.toList(growable: false);
}

OpsJson projectPendingRestaurantNotificationReads({
  required OpsJson inbox,
  required List<PendingEvent> events,
  required String branchId,
  required String actorId,
}) {
  final rawNotifications = inbox['notifications'];
  if (rawNotifications is! List || events.isEmpty) return inbox;

  final notifications = rawNotifications
      .whereType<Map<String, dynamic>>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
  var unreadCount = (inbox['unread_count'] as num? ??
          notifications.where((item) => item['read_at'] == null).length)
      .toInt();

  void markRead(Map<String, dynamic> item) {
    if (item['read_at'] == null && item['_pending_read'] != true) {
      if (unreadCount > 0) unreadCount--;
      item['_pending_read'] = true;
    }
  }

  for (final event in events) {
    if (event.syncStatus != 'pending') continue;
    try {
      final decoded = jsonDecode(event.payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['queued_by_user_id'] != actorId ||
          decoded['branch_id'] != branchId) {
        continue;
      }
      if (decoded['action'] == 'mark_all_notifications_read') {
        for (final item in notifications) {
          markRead(item);
        }
        unreadCount = 0;
      } else if (decoded['action'] == 'mark_notification_read') {
        final notificationId = decoded['notification_id'];
        if (notificationId is String) {
          for (final item in notifications) {
            if (item['id'] == notificationId) markRead(item);
          }
        }
      }
    } on FormatException {
      // The outbox recovery panel remains responsible for malformed events.
    }
  }

  return {
    ...inbox,
    'notifications': notifications,
    'unread_count': unreadCount,
  };
}

final restaurantOutboxEventsProvider =
    StreamProvider.family<List<PendingEvent>, String>((ref, branchId) {
  return ref
      .watch(restaurantOpsRepositoryProvider)
      .watchOutstandingRestaurantEvents(branchId);
});

final restaurantOpsRepositoryProvider = Provider<RestaurantOpsRepository>((ref) {
  return RestaurantOpsRepository(
    Supabase.instance.client,
    ref.watch(localDatabaseProvider),
  );
});

class RestaurantSelectedBranchNotifier extends Notifier<String?> {
  int _restoreGeneration = 0;

  @override
  String? build() {
    final generation = ++_restoreGeneration;
    final repository = ref.read(restaurantOpsRepositoryProvider);
    ref.onDispose(() => _restoreGeneration++);
    unawaited(_restoreSelectedBranch(repository, generation));
    return null;
  }

  Future<void> _restoreSelectedBranch(
    RestaurantOpsRepository repository,
    int generation,
  ) async {
    final savedBranchId = await repository.fetchSelectedBranchId();
    if (generation == _restoreGeneration && state == null) {
      state = savedBranchId;
    }
  }

  void selectBranch(String branchId) {
    state = branchId;
    unawaited(ref.read(restaurantOpsRepositoryProvider).saveSelectedBranchId(branchId));
  }
}

final restaurantSelectedBranchProvider = NotifierProvider<
  RestaurantSelectedBranchNotifier,
  String?
>(RestaurantSelectedBranchNotifier.new);

final restaurantBranchesProvider = FutureProvider<List<OpsJson>>((ref) {
  return ref.watch(restaurantOpsRepositoryProvider).fetchBranches();
});

final restaurantDashboardProvider =
    FutureProvider.family<OpsJson, String>((ref, branchId) {
  return ref.watch(restaurantOpsRepositoryProvider).fetchDashboard(branchId);
});

final restaurantAttendanceHistoryProvider =
    FutureProvider.family<OpsJson, ({String branchId, String forDate})>((ref, key) {
  return ref
      .watch(restaurantOpsRepositoryProvider)
      .fetchAttendanceHistory(key.branchId, key.forDate);
});

final restaurantNotificationsProvider =
    FutureProvider.family<OpsJson, String>((ref, branchId) {
  return ref.watch(restaurantOpsRepositoryProvider).fetchNotifications(branchId);
});

final restaurantShiftCoverRequestsProvider =
    FutureProvider.family<OpsJson, String>((ref, branchId) {
  return ref
      .watch(restaurantOpsRepositoryProvider)
      .fetchShiftCoverRequests(branchId);
});

final restaurantRealtimeProvider =
    StreamProvider.family<void, String>((ref, branchId) {
  final client = Supabase.instance.client;
  final controller = StreamController<void>.broadcast();
  final subscriptions = <StreamSubscription<dynamic>>[];
  final changes = <Stream<List<Map<String, dynamic>>>>[
    client.from('restaurant_branches').stream(primaryKey: ['id']).eq('id', branchId),
    client.from('restaurant_time_sessions').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_areas').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_memberships').stream(primaryKey: ['branch_id', 'user_id']).eq('branch_id', branchId),
    client.from('restaurant_shifts').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_activity_templates').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_tasks').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_task_parts').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_incidents').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_absences').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_waste_bins').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_inspection_templates').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_inspection_items').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_inspections').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_inspection_results').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_waste_inspections').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_waste_inspection_results').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_shift_handoffs').stream(primaryKey: ['id']).eq('branch_id', branchId),
    client.from('restaurant_notifications').stream(primaryKey: ['id']).eq('branch_id', branchId),
  ];
  final userId = client.auth.currentUser?.id;
  if (userId != null) {
    changes.add(
      client
          .from('restaurant_notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', userId),
    );
  }
  for (final stream in changes) {
    subscriptions.add(stream.listen(
      (_) => controller.add(null),
      onError: (_) {},
    ));
  }
  subscriptions.add(Connectivity().onConnectivityChanged.listen(
    (_) => controller.add(null),
    onError: (_) {},
  ));
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(controller.close());
  });
  return controller.stream;
});

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

class PendingEvents extends Table {
  TextColumn get id => text()();
  TextColumn get eventType => text()();
  TextColumn get jobId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PendingMediaUploads extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text()();
  TextColumn get filePath => text()();
  TextColumn get mimeType => text().withDefault(const Constant('image/jpeg'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('saved'))();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [PendingEvents, PendingMediaUploads])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase() : super(_openConnection());

  LocalDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(pendingMediaUploads);
      }
    },
    beforeOpen: (_) async {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS restaurant_snapshots (
          cache_key TEXT PRIMARY KEY NOT NULL,
          payload TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS restaurant_local_preferences (
          user_id TEXT NOT NULL,
          preference_key TEXT NOT NULL,
          preference_value TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (user_id, preference_key)
        )
      ''');
    },
  );

  Future<void> saveRestaurantSnapshot(String key, String payload) async {
    await customStatement(
      'INSERT INTO restaurant_snapshots(cache_key, payload, updated_at) '
      'VALUES (?, ?, ?) ON CONFLICT(cache_key) DO UPDATE SET '
      'payload = excluded.payload, updated_at = excluded.updated_at',
      [
        Variable.withString(key),
        Variable.withString(payload),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
      ],
    );
    await customStatement(
      'DELETE FROM restaurant_snapshots WHERE updated_at < ?',
      [Variable.withString(
        DateTime.now().toUtc().subtract(const Duration(days: 90)).toIso8601String(),
      )],
    );
  }

  Future<Map<String, String>?> readRestaurantSnapshot(String key) async {
    final row = await customSelect(
      'SELECT payload, updated_at FROM restaurant_snapshots WHERE cache_key = ? LIMIT 1',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();
    if (row == null) return null;
    return {
      'payload': row.read<String>('payload'),
      'updated_at': row.read<String>('updated_at'),
    };
  }

  Future<void> saveRestaurantPreference({
    required String userId,
    required String key,
    required String value,
  }) async {
    await customStatement(
      'INSERT INTO restaurant_local_preferences(user_id, preference_key, preference_value, updated_at) '
      'VALUES (?, ?, ?, ?) ON CONFLICT(user_id, preference_key) DO UPDATE SET '
      'preference_value = excluded.preference_value, updated_at = excluded.updated_at',
      [
        Variable.withString(userId),
        Variable.withString(key),
        Variable.withString(value),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
      ],
    );
  }

  Future<String?> readRestaurantPreference({
    required String userId,
    required String key,
  }) async {
    final row = await customSelect(
      'SELECT preference_value FROM restaurant_local_preferences '
      'WHERE user_id = ? AND preference_key = ? LIMIT 1',
      variables: [Variable.withString(userId), Variable.withString(key)],
    ).getSingleOrNull();
    return row?.read<String>('preference_value');
  }

  Future<List<PendingEvent>> pendingEventsByAge() {
    return (select(pendingEvents)
          ..where((e) => e.syncStatus.equals('pending'))
          ..where(
            (e) =>
                e.nextRetryAt.isNull() |
                e.nextRetryAt.isSmallerOrEqualValue(DateTime.now()),
          )
          ..orderBy([
            (e) => OrderingTerm.asc(e.occurredAt),
            (e) => OrderingTerm.asc(e.id),
          ]))
        .get();
  }

  Stream<List<PendingEvent>> watchOutstandingRestaurantEvents(String branchId) {
    return (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account']))
          ..orderBy([
            (event) => OrderingTerm.asc(event.occurredAt),
            (event) => OrderingTerm.asc(event.id),
          ]))
        .watch();
  }

  Stream<List<PendingEvent>> watchOutboxAttentionEvents() => (select(pendingEvents)
        ..where((event) => event.syncStatus.isIn(const ['failed', 'waiting_account']))
        ..orderBy([(event) => OrderingTerm.asc(event.occurredAt)]))
      .watch();

  Future<void> resumeWaitingEvents() => (update(pendingEvents)
        ..where((event) => event.syncStatus.equals('waiting_account')))
      .write(const PendingEventsCompanion(
        syncStatus: Value('pending'),
        nextRetryAt: Value(null),
        errorMessage: Value(null),
      ));

  Future<int> pendingCount() async {
    final query = selectOnly(pendingEvents)
      ..addColumns([pendingEvents.id.count()])
      ..where(pendingEvents.syncStatus.equals('pending'));
    final row = await query.getSingle();
    return row.read(pendingEvents.id.count()) ?? 0;
  }

  Stream<int> watchPendingCount() {
    final countColumn = pendingEvents.id.count();
    return (selectOnly(pendingEvents)
          ..addColumns([countColumn])
          ..where(pendingEvents.syncStatus.equals('pending')))
        .watchSingle()
        .map((row) => row.read(countColumn) ?? 0);
  }

  Future<void> retryFailedEvent(String eventId) =>
      (update(pendingEvents)
            ..where((event) => event.id.equals(eventId) & event.syncStatus.equals('failed')))
          .write(const PendingEventsCompanion(
            syncStatus: Value('pending'),
            retryCount: Value(0),
            nextRetryAt: Value(null),
            errorMessage: Value(null),
          ));

  Future<int> pendingMediaUploadCount({String? jobId}) async {
    final query = selectOnly(pendingMediaUploads)
      ..addColumns([pendingMediaUploads.id.count()])
      ..where(pendingMediaUploads.syncStatus.isIn(const ['saved', 'pending']));

    if (jobId != null) {
      query.where(pendingMediaUploads.jobId.equals(jobId));
    }

    final row = await query.getSingle();
    return row.read(pendingMediaUploads.id.count()) ?? 0;
  }

  Stream<int> watchPendingMediaUploadCount({String? jobId}) {
    final query = selectOnly(pendingMediaUploads)
      ..addColumns([pendingMediaUploads.id.count()])
      ..where(pendingMediaUploads.syncStatus.isIn(const ['saved', 'pending']));

    if (jobId != null) {
      query.where(pendingMediaUploads.jobId.equals(jobId));
    }

    return query
        .watchSingle()
        .map((row) => row.read(pendingMediaUploads.id.count()) ?? 0);
  }

  Stream<List<PendingMediaUpload>> watchPendingMediaUploadsForJob(
    String jobId,
  ) {
    return (select(pendingMediaUploads)
          ..where((draft) => draft.jobId.equals(jobId))
          ..where((draft) => draft.syncStatus.isNotValue('uploaded'))
          ..orderBy([(draft) => OrderingTerm.desc(draft.createdAt)]))
        .watch();
  }

  Future<void> savePendingMediaUpload(PendingMediaUploadsCompanion draft) {
    return into(
      pendingMediaUploads,
    ).insert(draft, mode: InsertMode.insertOrReplace);
  }

  Future<PendingMediaUpload?> findPendingMediaUpload(String id) {
    return (select(
      pendingMediaUploads,
    )..where((draft) => draft.id.equals(id))).getSingleOrNull();
  }

  Future<void> markPendingMediaUploadUploaded(String id) {
    return (update(
      pendingMediaUploads,
    )..where((draft) => draft.id.equals(id))).write(
      const PendingMediaUploadsCompanion(syncStatus: Value('uploaded')),
    );
  }

  Future<void> markPendingMediaUploadFailed(
    String id,
    String error, {
    required int retryCount,
  }) {
    return (update(
      pendingMediaUploads,
    )..where((draft) => draft.id.equals(id))).write(
      PendingMediaUploadsCompanion(
        syncStatus: const Value('saved'),
        errorMessage: Value(error),
        retryCount: Value(retryCount),
      ),
    );
  }

  Future<void> deletePendingMediaUpload(String id) {
    return (delete(
      pendingMediaUploads,
    )..where((draft) => draft.id.equals(id))).go();
  }

  Future<void> markSynced(String eventId) {
    return (update(pendingEvents)..where((e) => e.id.equals(eventId))).write(
      const PendingEventsCompanion(syncStatus: Value('synced')),
    );
  }

  Future<bool> hasOutstandingRestaurantEvidence(String objectPath) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account'])))
        .get();
    for (final event in events) {
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['action'] == 'upload_evidence' &&
            payload['object_path'] == objectPath) {
          return true;
        }
      } on FormatException {
        // The normal outbox handler will surface malformed rows.
      }
    }
    return false;
  }

  Future<bool> hasOutstandingRestaurantClockEvent({
    required String branchId,
    required String actorId,
  }) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account']))
          ..orderBy([(event) => OrderingTerm.asc(event.createdAt)])
        ).get();
    for (final event in events) {
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['queued_by_user_id'] == actorId &&
            payload['action'] == 'record_time_event' &&
            payload['branch_id'] == branchId) {
          return true;
        }
      } on FormatException {
        // Leave malformed events for the normal outbox recovery flow.
      }
    }
    return false;
  }

  Future<bool> hasEarlierUnresolvedRestaurantClockEvent({
    required PendingEvent currentEvent,
    required String branchId,
    required String actorId,
  }) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account'])))
        .get();
    for (final event in events) {
      final earlier = event.createdAt.isBefore(currentEvent.createdAt) ||
          (event.createdAt.isAtSameMomentAs(currentEvent.createdAt) &&
              event.id.compareTo(currentEvent.id) < 0);
      if (event.id == currentEvent.id || !earlier) continue;
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['queued_by_user_id'] == actorId &&
            payload['action'] == 'record_time_event' &&
            payload['branch_id'] == branchId) {
          return true;
        }
      } on FormatException {
        // Leave malformed events for the normal outbox recovery flow.
      }
    }
    return false;
  }

  Future<bool> hasEarlierUnresolvedRestaurantShiftCoverRequest({
    required PendingEvent currentEvent,
    required String branchId,
    required String actorId,
    required String clientEventId,
  }) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account'])))
        .get();
    for (final event in events) {
      final earlier = event.createdAt.isBefore(currentEvent.createdAt) ||
          (event.createdAt.isAtSameMomentAs(currentEvent.createdAt) &&
              event.id.compareTo(currentEvent.id) < 0);
      if (event.id == currentEvent.id || !earlier) continue;
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['queued_by_user_id'] == actorId &&
            payload['branch_id'] == branchId &&
            payload['action'] == 'request_shift_cover' &&
            payload['client_event_id'] == clientEventId) {
          return true;
        }
      } on FormatException {
        // Leave malformed events for the normal outbox recovery flow.
      }
    }
    return false;
  }

  Future<bool> hasUnresolvedRestaurantShiftCoverRequest({
    required String branchId,
    required String actorId,
    required String clientEventId,
  }) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account'])))
        .get();
    for (final event in events) {
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['queued_by_user_id'] == actorId &&
            payload['branch_id'] == branchId &&
            payload['action'] == 'request_shift_cover' &&
            payload['client_event_id'] == clientEventId) {
          return true;
        }
      } on FormatException {
        // Leave malformed events for the normal outbox recovery flow.
      }
    }
    return false;
  }

  Future<bool> hasEarlierUnresolvedRestaurantTaskAction({
    required PendingEvent currentEvent,
    required String branchId,
    required String actorId,
    required String taskId,
    required String? partId,
  }) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account']))
          ..orderBy([
            (event) => OrderingTerm.asc(event.occurredAt),
            (event) => OrderingTerm.asc(event.id),
          ]))
        .get();
    for (final event in events) {
      final earlier = event.occurredAt.isBefore(currentEvent.occurredAt) ||
          (event.occurredAt.isAtSameMomentAs(currentEvent.occurredAt) &&
              event.id.compareTo(currentEvent.id) < 0);
      if (event.id == currentEvent.id || !earlier) continue;
      try {
        final payload = jsonDecode(event.payload);
        if (payload is Map<String, dynamic> &&
            payload['queued_by_user_id'] == actorId &&
            payload['action'] == 'task_action' &&
            payload['branch_id'] == branchId &&
            payload['task_id'] == taskId &&
            payload['part_id'] == partId) {
          return true;
        }
      } on FormatException {
        // Leave malformed events for the normal outbox recovery flow.
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> latestOutstandingRestaurantClockState({
    required String branchId,
    required String actorId,
  }) async {
    final events = await (select(pendingEvents)
          ..where((event) =>
              event.jobId.equals(branchId) &
              event.eventType.equals('restaurant_ops') &
              event.syncStatus.isIn(const ['pending', 'failed', 'waiting_account']))
          ..orderBy([(event) => OrderingTerm.asc(event.createdAt)])
        ).get();
    Map<String, dynamic>? latestState;
    for (final event in events) {
      try {
        final payload = jsonDecode(event.payload);
        if (payload is! Map<String, dynamic> ||
            payload['queued_by_user_id'] != actorId ||
            payload['action'] != 'record_time_event' ||
            payload['branch_id'] != branchId) {
          continue;
        }
        final eventType = payload['event_type'];
        final occurredAt = payload['occurred_at'];
        if (!const {'clock_in', 'clock_out'}.contains(eventType) || occurredAt is! String) continue;
        latestState = {
          'clocked_in': eventType == 'clock_in',
          'clock_in_at': eventType == 'clock_in' ? occurredAt : null,
        };
      } on FormatException {
        // Leave malformed events for the normal outbox recovery flow.
      }
    }
    return latestState;
  }

  Future<void> markFailed(String eventId, String error, int retryCount) {
    final backoffSeconds = _exponentialBackoff(retryCount);
    final nextRetry = DateTime.now().add(Duration(seconds: backoffSeconds));
    return (update(pendingEvents)..where((e) => e.id.equals(eventId))).write(
      PendingEventsCompanion(
        syncStatus: const Value('pending'),
        errorMessage: Value(error),
        retryCount: Value(retryCount),
        nextRetryAt: Value(nextRetry),
      ),
    );
  }

  Future<void> markPermanentlyFailed(String eventId, String error) {
    return (update(pendingEvents)..where((e) => e.id.equals(eventId))).write(
      PendingEventsCompanion(
        syncStatus: const Value('failed'),
        errorMessage: Value(error),
      ),
    );
  }

  Future<void> markWaitingForAccount(String eventId) =>
      (update(pendingEvents)..where((event) => event.id.equals(eventId))).write(
        const PendingEventsCompanion(
          syncStatus: Value('waiting_account'),
          nextRetryAt: Value(null),
          errorMessage: Value('Sign in with the account that saved this change.'),
        ),
      );

  Future<void> cleanSynced() {
    return (delete(
      pendingEvents,
    )..where((e) => e.syncStatus.equals('synced'))).go();
  }

  int _exponentialBackoff(int retryCount) {
    // 5s, 10s, 20s, 40s, 80s cap
    const base = 5;
    final seconds = base * (1 << retryCount);
    return seconds.clamp(5, 80);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pollo_movil_local.sqlite');

    // Keep a persistent encryption key. Never open the same on-disk database
    // with a session-only key that would make queued offline records unreadable.
    const storage = FlutterSecureStorage();
    const keyName = 'pollo_movil_db_key';
    String dbKey;
    try {
      final existing = await storage.read(key: keyName);
      if (existing != null && existing.isNotEmpty) {
        dbKey = existing;
      } else {
        dbKey = _generateKey(32);
        await storage.write(key: keyName, value: dbKey);
      }
    } on Object {
      throw StateError(
        'Secure storage is unavailable; offline data cannot be persisted safely.',
      );
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$dbKey'");
      },
    );
  });
}

/// Generates a cryptographically secure random key of [length] characters.
String _generateKey(int length) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rng = Random.secure();
  return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
}

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final db = LocalDatabase();
  ref.onDispose(db.close);
  return db;
});

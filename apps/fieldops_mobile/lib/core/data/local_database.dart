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
  );

  Future<List<PendingEvent>> pendingEventsByAge() {
    return (select(pendingEvents)
          ..where((e) => e.syncStatus.equals('pending'))
          ..where(
            (e) =>
                e.nextRetryAt.isNull() |
                e.nextRetryAt.isSmallerOrEqualValue(DateTime.now()),
          )
          ..orderBy([(e) => OrderingTerm.asc(e.occurredAt)]))
        .get();
  }

  Future<int> pendingCount() async {
    final query = selectOnly(pendingEvents)
      ..addColumns([pendingEvents.id.count()])
      ..where(pendingEvents.syncStatus.equals('pending'));
    final row = await query.getSingle();
    return row.read(pendingEvents.id.count()) ?? 0;
  }

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

  Future<void> cleanOldFailed({Duration olderThan = const Duration(days: 7)}) {
    final cutoff = DateTime.now().subtract(olderThan);
    return (delete(pendingEvents)
          ..where(
            (e) =>
                e.syncStatus.equals('failed') &
                e.createdAt.isSmallerThanValue(cutoff),
          ))
        .go();
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
    final file = File('${dir.path}/fieldops_local.sqlite');

    // Retrieve or generate the encryption key. Secure storage can fail on
    // fresh installs / locked keychains / OEM quirks — fall back to a
    // session-only key so the DB still opens instead of crashing the app.
    const storage = FlutterSecureStorage();
    const keyName = 'fieldops_db_key';
    String dbKey;
    try {
      final existing = await storage.read(key: keyName);
      if (existing != null && existing.isNotEmpty) {
        dbKey = existing;
      } else {
        dbKey = _generateKey(32);
        try {
          await storage.write(key: keyName, value: dbKey);
        } on Object {
          // Best-effort persist; proceed with in-memory key.
        }
      }
    } on Object {
      // Keychain unavailable — use a transient key so the app still boots.
      dbKey = _generateKey(32);
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

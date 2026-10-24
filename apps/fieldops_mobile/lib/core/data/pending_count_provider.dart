import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits the pending sync count as soon as the local outbox changes.
final pendingEventCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database.watchPendingCount();
});

/// Failed outbox events remain on-device until a worker or manager retries them.
/// The payload is deliberately not rendered by the UI because it can contain
/// location data or operational notes.
final outboxAttentionEventsProvider = StreamProvider<List<PendingEvent>>((ref) {
  return ref.watch(localDatabaseProvider).watchOutboxAttentionEvents();
});

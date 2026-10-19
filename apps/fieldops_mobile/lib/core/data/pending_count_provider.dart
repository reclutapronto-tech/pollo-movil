import 'dart:async';

import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Polls the local database every 5 seconds for the count of pending sync
/// events. The [Timer] is properly cancelled when the provider is disposed,
/// preventing database polls from continuing after the widget tree is torn down.
final pendingEventCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(localDatabaseProvider);
  final controller = StreamController<int>();

  // Immediately fetch the current count.
  database.pendingCount().then((count) {
    if (!controller.isClosed) controller.add(count);
  });

  final timer = Timer.periodic(const Duration(seconds: 5), (_) async {
    try {
      final count = await database.pendingCount();
      if (!controller.isClosed) controller.add(count);
    } on Exception catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  });

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

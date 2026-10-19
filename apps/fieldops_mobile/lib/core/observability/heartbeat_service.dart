import 'dart:async';

import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Worker "last seen" heartbeat (FUX-015).
///
/// Calls the `touch_last_seen` RPC every [interval] while the app is
/// foregrounded, plus once immediately on [start] (app launch / resume).
/// The web /workers and /crew boards use `users.last_seen_at` to flag
/// clocked-in workers whose phone has gone dark.
///
/// Failures are swallowed: a heartbeat must never surface an error to the
/// worker or block any flow. Offline pings are simply lost — the next
/// successful ping self-heals the timestamp.
class HeartbeatService {
  HeartbeatService({this.interval = const Duration(minutes: 4)});

  final Duration interval;
  Timer? _timer;

  /// Idempotent: safe to call on every resume.
  void start() {
    _timer?.cancel();
    _ping();
    _timer = Timer.periodic(interval, (_) => _ping());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ping() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return;
      await client.rpc<void>('touch_last_seen');
    } on Object {
      // Never block or surface — see class docs.
    }
  }
}

final heartbeatServiceProvider = Provider<HeartbeatService>((ref) {
  final service = HeartbeatService();
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return service; // start() becomes a harmless no-op ping loop guard below
  }
  ref.onDispose(service.stop);
  return service;
});

import 'dart:async';

import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

// GPS breadcrumb sampling interval (configurable)
const _defaultIntervalMinutes = 10;

/// Periodically samples GPS while worker is clocked in.
/// Stores breadcrumb points locally for supervisor replay.
///
/// Privacy: Only active while clocked in. Never tracks off-clock.
class BreadcrumbService {
  BreadcrumbService({required this.database, Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final LocalDatabase database;
  final Uuid _uuid;
  Timer? _timer;
  String? _activeJobId;

  void start({required String jobId, int intervalMinutes = _defaultIntervalMinutes}) {
    stop();
    _activeJobId = jobId;
    _timer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) => _samplePosition(),
    );
    // Sample immediately on start
    _samplePosition();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _activeJobId = null;
  }

  Future<void> _samplePosition() async {
    if (_activeJobId == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 10));

      // Store as a pending event for sync
      await database.into(database.pendingEvents).insert(
            PendingEventsCompanion.insert(
              id: _uuid.v4(),
              eventType: 'breadcrumb',
              jobId: _activeJobId!,
              payload:
                  '{"lat":${position.latitude},"lng":${position.longitude},"accuracy_m":${position.accuracy},"sampled_at":"${DateTime.now().toUtc().toIso8601String()}"}',
              occurredAt: DateTime.now().toUtc(),
            ),
          );
    } on Exception catch (_) {
      // GPS sampling failure is non-fatal — skip this sample
    }
  }
}

import 'dart:typed_data';

import 'package:fieldops_mobile/features/timecards/domain/timecard_signature.dart';

abstract class TimecardRepository {
  /// Fetches timecard periods for the current worker.
  Future<List<TimecardPeriod>> fetchMyTimecards();

  /// Worker signs their timecard with optional signature image.
  Future<void> signTimecard(String timecardId, {Uint8List? signatureImage});
}

class TimecardRepositoryException implements Exception {
  const TimecardRepositoryException(this.message);
  final String message;

  @override
  String toString() => 'TimecardRepositoryException: $message';
}

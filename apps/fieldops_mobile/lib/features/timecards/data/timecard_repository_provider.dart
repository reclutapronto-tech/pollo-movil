import 'dart:typed_data';

import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/timecards/data/supabase_timecard_repository.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_repository.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_signature.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final timecardRepositoryProvider = Provider<TimecardRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredTimecardRepository();
  }
  return SupabaseTimecardRepository(Supabase.instance.client);
});

class _UnconfiguredTimecardRepository implements TimecardRepository {
  const _UnconfiguredTimecardRepository();

  @override
  Future<List<TimecardPeriod>> fetchMyTimecards() {
    throw const TimecardRepositoryException('Missing Supabase configuration.');
  }

  @override
  Future<void> signTimecard(String timecardId, {Uint8List? signatureImage}) {
    throw const TimecardRepositoryException('Missing Supabase configuration.');
  }
}

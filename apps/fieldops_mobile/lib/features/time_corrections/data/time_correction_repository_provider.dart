import 'package:fieldops_mobile/features/time_corrections/data/supabase_time_correction_repository.dart';
import 'package:fieldops_mobile/features/time_corrections/domain/time_correction_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final timeCorrectionRepositoryProvider = Provider<TimeCorrectionRepository>((ref) {
  final client = Supabase.instance.client;
  return SupabaseTimeCorrectionRepository(client);
});

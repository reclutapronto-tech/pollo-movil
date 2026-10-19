import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/history/data/supabase_history_repository.dart';
import 'package:fieldops_mobile/features/history/domain/history_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final env = ref.watch(fieldOpsEnvironmentProvider);
  if (!env.isConfigured) return _UnconfiguredHistoryRepository();
  return SupabaseHistoryRepository(client: Supabase.instance.client);
});

class _UnconfiguredHistoryRepository implements HistoryRepository {
  @override
  Future<List<HistoryEntry>> fetchHistory({int limit = 50}) async => [];

  @override
  Future<HistorySummary> fetchSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    return const HistorySummary();
  }
}

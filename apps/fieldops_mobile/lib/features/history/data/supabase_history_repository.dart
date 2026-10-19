import 'package:fieldops_mobile/features/history/domain/history_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseHistoryRepository implements HistoryRepository {
  SupabaseHistoryRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  Future<List<HistoryEntry>> fetchHistory({int limit = 50}) async {
    try {
      final response = await _client.functions.invoke(
        'worker_history',
        body: {'action': 'list', 'limit': limit},
      );

      final data = response.data as Map<String, dynamic>? ?? {};
      final entries = data['entries'] as List<dynamic>? ?? [];

      return entries
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception catch (e) {
      throw HistoryRepositoryException(e.toString());
    }
  }

  @override
  Future<HistorySummary> fetchSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'worker_history',
        body: {
          'action': 'summary',
          'from': from.toIso8601String(),
          'to': to.toIso8601String(),
        },
      );

      final data = response.data as Map<String, dynamic>? ?? {};

      return HistorySummary(
        totalHours: (data['total_hours'] as num?)?.toDouble() ?? 0,
        regularHours: (data['regular_hours'] as num?)?.toDouble() ?? 0,
        otHours: (data['ot_hours'] as num?)?.toDouble() ?? 0,
        totalJobs: (data['total_jobs'] as num?)?.toInt() ?? 0,
        totalPhotos: (data['total_photos'] as num?)?.toInt() ?? 0,
        totalTasks: (data['total_tasks'] as num?)?.toInt() ?? 0,
      );
    } on Exception catch (e) {
      throw HistoryRepositoryException(e.toString());
    }
  }
}

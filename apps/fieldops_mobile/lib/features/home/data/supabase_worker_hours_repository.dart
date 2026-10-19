import 'dart:io';

import 'package:fieldops_mobile/features/home/domain/worker_hours_repository.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_snapshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseWorkerHoursRepository implements WorkerHoursRepository {
  const SupabaseWorkerHoursRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<WorkerHoursSnapshot> fetchSummary() async {
    try {
      final response = await _client.functions.invoke(
        'worker_hours',
        method: HttpMethod.get,
        headers: const {'X-Client-Version': 'fieldops-mobile'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const WorkerHoursRepositoryException.unknown(
          'Worker hours response was malformed.',
        );
      }

      final summary = payload['summary'];
      if (summary is! Map<String, dynamic>) {
        throw const WorkerHoursRepositoryException.unknown(
          'Worker hours summary was malformed.',
        );
      }

      return WorkerHoursSnapshot.fromJson(summary);
    } on SocketException {
      throw const WorkerHoursRepositoryException.offline();
    } on HttpException {
      throw const WorkerHoursRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const WorkerHoursRepositoryException.offline();
      }
      throw WorkerHoursRepositoryException.unknown(
        'Worker hours request failed (${error.status}).',
      );
    }
  }
}

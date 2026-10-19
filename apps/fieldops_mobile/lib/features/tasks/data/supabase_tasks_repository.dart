import 'dart:io';

import 'package:fieldops_mobile/features/tasks/domain/task_item.dart';
import 'package:fieldops_mobile/features/tasks/domain/tasks_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseTasksRepository implements TasksRepository {
  const SupabaseTasksRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<List<TaskItem>> fetchTasks({required String jobId}) async {
    try {
      final response = await _client.functions.invoke(
        'tasks',
        method: HttpMethod.get,
        headers: {'X-Client-Version': 'fieldops-mobile'},
        queryParameters: {'job_id': jobId},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const TasksRepositoryException.unknown('Task response was malformed.');
      }

      final tasks = payload['tasks'] as List<dynamic>? ?? const [];
      return tasks
          .whereType<Map<String, dynamic>>()
          .map(TaskItem.fromJson)
          .toList(growable: false);
    } on SocketException {
      throw const TasksRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const TasksRepositoryException.offline();
      throw TasksRepositoryException.unknown('Tasks request failed (${error.status}).');
    }
  }

  @override
  Future<void> updateTaskStatus({
    required String taskId,
    required String action,
    String? note,
    String? mediaAssetId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'tasks',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'task_id': taskId,
          'action': action,
          if (note != null) 'note': note,
          if (mediaAssetId != null) 'media_asset_id': mediaAssetId,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const TasksRepositoryException.unknown('Task update response was malformed.');
      }
    } on SocketException {
      throw const TasksRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const TasksRepositoryException.offline();
      final message = error.details?.toString() ?? '';
      if (message.contains('PHOTO_REQUIRED')) {
        throw const TasksRepositoryException.photoRequired();
      }
      if (message.contains('INVALID_TRANSITION')) {
        throw TasksRepositoryException.invalidTransition(message);
      }
      throw TasksRepositoryException.unknown('Task update failed (${error.status}).');
    }
  }
}

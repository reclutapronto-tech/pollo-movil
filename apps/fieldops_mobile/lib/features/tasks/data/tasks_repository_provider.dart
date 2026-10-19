import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/tasks/data/supabase_tasks_repository.dart';
import 'package:fieldops_mobile/features/tasks/domain/task_item.dart';
import 'package:fieldops_mobile/features/tasks/domain/tasks_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredTasksRepository();
  }
  return SupabaseTasksRepository(Supabase.instance.client);
});

class _UnconfiguredTasksRepository implements TasksRepository {
  const _UnconfiguredTasksRepository();

  @override
  Future<List<TaskItem>> fetchTasks({required String jobId}) {
    throw const TasksRepositoryException.unknown('Missing Supabase configuration.');
  }

  @override
  Future<void> updateTaskStatus({
    required String taskId,
    required String action,
    String? note,
    String? mediaAssetId,
  }) {
    throw const TasksRepositoryException.unknown('Missing Supabase configuration.');
  }
}

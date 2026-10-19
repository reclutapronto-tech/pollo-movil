import 'package:fieldops_mobile/features/tasks/data/tasks_repository_provider.dart';
import 'package:fieldops_mobile/features/tasks/domain/task_item.dart';
import 'package:fieldops_mobile/features/tasks/domain/tasks_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stores the job ID for the active task list. Override via ProviderScope.
final activeTaskJobIdProvider = Provider<String>((_) => '');

final tasksControllerProvider =
    AsyncNotifierProvider<TasksController, List<TaskItem>>(
  TasksController.new,
);

class TasksController extends AsyncNotifier<List<TaskItem>> {
  @override
  Future<List<TaskItem>> build() {
    final jobId = ref.watch(activeTaskJobIdProvider);
    if (jobId.isEmpty) return Future.value([]);
    return ref.read(tasksRepositoryProvider).fetchTasks(jobId: jobId);
  }

  Future<void> reload() async {
    final jobId = ref.read(activeTaskJobIdProvider);
    if (jobId.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(tasksRepositoryProvider).fetchTasks(jobId: jobId),
    );
  }

  Future<void> updateStatus({
    required String taskId,
    required String action,
    String? note,
    String? mediaAssetId,
  }) async {
    try {
      await ref.read(tasksRepositoryProvider).updateTaskStatus(
            taskId: taskId,
            action: action,
            note: note,
            mediaAssetId: mediaAssetId,
          );
      await reload();
    } on TasksRepositoryException {
      rethrow;
    }
  }
}

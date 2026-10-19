import 'package:fieldops_mobile/features/tasks/domain/task_item.dart';

abstract class TasksRepository {
  Future<List<TaskItem>> fetchTasks({required String jobId});
  Future<void> updateTaskStatus({
    required String taskId,
    required String action,
    String? note,
    String? mediaAssetId,
  });
}

enum TasksRepositoryErrorType { offline, photoRequired, invalidTransition, unknown }

class TasksRepositoryException implements Exception {
  const TasksRepositoryException._({
    required this.type,
    required this.message,
  });

  const TasksRepositoryException.offline()
      : this._(
          type: TasksRepositoryErrorType.offline,
          message: 'No connection available.',
        );

  const TasksRepositoryException.photoRequired()
      : this._(
          type: TasksRepositoryErrorType.photoRequired,
          message: 'This task requires a photo before it can be completed.',
        );

  const TasksRepositoryException.invalidTransition(String detail)
      : this._(
          type: TasksRepositoryErrorType.invalidTransition,
          message: detail,
        );

  const TasksRepositoryException.unknown([
    String message = 'Task update could not be completed.',
  ]) : this._(type: TasksRepositoryErrorType.unknown, message: message);

  final TasksRepositoryErrorType type;
  final String message;

  bool get isPhotoRequired => type == TasksRepositoryErrorType.photoRequired;

  @override
  String toString() => 'TasksRepositoryException($type): $message';
}

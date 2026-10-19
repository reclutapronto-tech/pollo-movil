import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/tasks/domain/task_item.dart';
import 'package:fieldops_mobile/features/tasks/domain/tasks_repository.dart';
import 'package:fieldops_mobile/features/tasks/presentation/tasks_controller.dart';
import 'package:fieldops_mobile/features/tasks/presentation/widgets/task_tile.dart';
import 'package:fieldops_mobile/features/tasks/presentation/widgets/tasks_empty_state.dart';
import 'package:fieldops_mobile/features/tasks/presentation/widgets/tasks_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({
    super.key,
    required this.jobId,
    required this.jobName,
  });

  final String jobId;
  final String jobName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksState = ref.watch(tasksControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(jobName),
        leading: const BackButton(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Task checklist', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Complete each task. Photo-required tasks need a proof photo before marking done.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: tasksState.when(
                data: (tasks) => _TaskList(
                  tasks: tasks,
                  jobId: jobId,
                  onRefresh: () => ref
                      .read(tasksControllerProvider.notifier)
                      .reload(),
                ),
                loading: () => const SkeletonLoader(itemCount: 4),
                error: (error, _) {
                  final repoError = error is TasksRepositoryException
                      ? error
                      : const TasksRepositoryException.unknown();
                  return TasksErrorState(
                    message: repoError.message,
                    onRetry: () => ref
                        .read(tasksControllerProvider.notifier)
                        .reload(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    required this.jobId,
    required this.onRefresh,
  });

  final List<TaskItem> tasks;
  final String jobId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            TasksEmptyState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => TaskTile(
          key: ValueKey(tasks[index].taskId),
          task: tasks[index],
          jobId: jobId,
        ),
      ),
    );
  }
}

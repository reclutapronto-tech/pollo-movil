import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_capture_screen.dart';
import 'package:fieldops_mobile/features/tasks/domain/task_item.dart';
import 'package:fieldops_mobile/features/tasks/domain/tasks_repository.dart';
import 'package:fieldops_mobile/features/tasks/presentation/tasks_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskTile extends ConsumerStatefulWidget {
  const TaskTile({super.key, required this.task, required this.jobId});

  final TaskItem task;
  final String jobId;

  @override
  ConsumerState<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<TaskTile> {
  bool _isUpdating = false;
  String? _errorMessage;

  Future<void> _handleAction(String action) async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
    });

    try {
      // If completing a photo-required task, open camera first
      if (action == 'complete' && widget.task.requiresPhoto) {
        if (!mounted) return;
        final result = await Navigator.of(context).push<PhotoCaptureResult?>(
          MaterialPageRoute<PhotoCaptureResult?>(
            builder: (_) => CameraCaptureScreen(
              jobId: widget.jobId,
              jobName: 'Photo for: ${widget.task.name}',
            ),
          ),
        );

        if (result == null || !result.isUploaded || !mounted) {
          setState(() => _isUpdating = false);
          return;
        }
        await ref
            .read(tasksControllerProvider.notifier)
            .updateStatus(
              taskId: widget.task.taskId,
              action: action,
              mediaAssetId: result.mediaAssetId,
            );
        return;
      }

      await ref
          .read(tasksControllerProvider.notifier)
          .updateStatus(taskId: widget.task.taskId, action: action);
    } on TasksRepositoryException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final task = widget.task;

    final Color statusColor;
    final IconData statusIcon;

    switch (task.status) {
      case 'completed':
        statusColor = palette.success;
        statusIcon = Icons.check_circle_rounded;
      case 'in_progress':
        statusColor = palette.signal;
        statusIcon = Icons.play_circle_rounded;
      case 'blocked':
        statusColor = palette.danger;
        statusIcon = Icons.block_rounded;
      case 'skipped':
        statusColor = palette.steel;
        statusIcon = Icons.skip_next_rounded;
      default:
        statusColor = palette.steel;
        statusIcon = Icons.radio_button_unchecked_rounded;
    }

    return Semantics(
      label:
          '${task.name}. Status: ${task.status}${task.requiresPhoto ? '. Photo required' : ''}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.name,
                                style: textTheme.titleLarge?.copyWith(
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (task.requiresPhoto)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  size: 18,
                                  color: task.isCompleted
                                      ? palette.steel
                                      : palette.signal,
                                  semanticLabel: 'Photo required',
                                ),
                              ),
                          ],
                        ),
                        if (task.description != null) ...[
                          const SizedBox(height: 4),
                          Text(task.description!, style: textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: textTheme.bodyMedium?.copyWith(color: palette.danger),
                ),
              ],
              if (task.isActionable) ...[
                const SizedBox(height: 12),
                _TaskActions(
                  task: task,
                  isUpdating: _isUpdating,
                  onAction: _handleAction,
                  palette: palette,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({
    required this.task,
    required this.isUpdating,
    required this.onAction,
    required this.palette,
  });

  final TaskItem task;
  final bool isUpdating;
  final Future<void> Function(String) onAction;
  final FieldOpsPalette palette;

  @override
  Widget build(BuildContext context) {
    if (isUpdating) {
      return const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final actions = <Widget>[];

    if (task.status == 'not_started') {
      actions.add(
        _ActionButton(
          label: 'Start',
          icon: Icons.play_arrow_rounded,
          color: palette.signal,
          onTap: () => onAction('start'),
        ),
      );
    }

    if (task.status == 'in_progress' || task.status == 'blocked') {
      actions.add(
        _ActionButton(
          label: task.requiresPhoto ? 'Photo + Complete' : 'Complete',
          icon: Icons.check_rounded,
          color: palette.success,
          onTap: () => onAction('complete'),
        ),
      );
    }

    if (task.status == 'in_progress') {
      actions.add(
        _ActionButton(
          label: 'Block',
          icon: Icons.block_rounded,
          color: palette.danger,
          onTap: () => onAction('block'),
        ),
      );
    }

    if (task.status != 'completed' && task.status != 'skipped') {
      actions.add(
        _ActionButton(
          label: 'Skip',
          icon: Icons.skip_next_rounded,
          color: palette.steel,
          onTap: () => onAction('skip'),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: actions);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

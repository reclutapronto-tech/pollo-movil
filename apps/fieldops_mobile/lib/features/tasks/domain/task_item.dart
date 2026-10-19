class TaskItem {
  const TaskItem({
    required this.taskId,
    required this.name,
    required this.status,
    required this.sortOrder,
    required this.requiresPhoto,
    this.description,
    this.assignedTo,
    this.completedAt,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      taskId: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed task',
      status: json['status'] as String? ?? 'not_started',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      requiresPhoto: json['requires_photo'] as bool? ?? false,
      description: json['description'] as String?,
      assignedTo: json['assigned_to'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );
  }

  final String taskId;
  final String name;
  final String status;
  final int sortOrder;
  final bool requiresPhoto;
  final String? description;
  final String? assignedTo;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';
  bool get isSkipped => status == 'skipped';
  bool get isTerminal => isCompleted || isSkipped;
  bool get isActionable => !isTerminal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TaskItem && taskId == other.taskId;

  @override
  int get hashCode => taskId.hashCode;
}

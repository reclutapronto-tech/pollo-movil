import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/pto/data/supabase_pto_repository.dart';
import 'package:fieldops_mobile/features/pto/domain/pto_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Admin screen: view + edit every (worker × pto_type × year) allocation
/// slot. Backs the `pto.allocations_list` + `pto.allocations_upsert`
/// edge function actions (same endpoint the web /settings/pto-allocations
/// page uses).
class PtoAllocationsScreen extends ConsumerStatefulWidget {
  const PtoAllocationsScreen({super.key});

  @override
  ConsumerState<PtoAllocationsScreen> createState() =>
      _PtoAllocationsScreenState();
}

class _PtoAllocationsScreenState extends ConsumerState<PtoAllocationsScreen> {
  static const _ptoTypes = ['vacation', 'sick', 'personal'];

  int _year = DateTime.now().toUtc().year;
  bool _loading = true;
  String? _error;
  // Grouped by user → pto_type → allocation
  final Map<String, Map<String, PtoAllocation>> _byUser = {};
  final Map<String, String> _names = {};
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allocations = await ref
          .read(ptoRepositoryProvider)
          .fetchAllocations(year: _year);
      final grouped = <String, Map<String, PtoAllocation>>{};
      final names = <String, String>{};
      for (final a in allocations) {
        grouped.putIfAbsent(a.userId, () => {})[a.ptoType] = a;
        if (a.workerName != null && a.workerName!.isNotEmpty) {
          names[a.userId] = a.workerName!;
        }
      }
      if (!mounted) return;
      setState(() {
        _byUser
          ..clear()
          ..addAll(grouped);
        _names
          ..clear()
          ..addAll(names);
        _loading = false;
      });
    } on PTORepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _edit(String userId, String ptoType) async {
    final current = _byUser[userId]?[ptoType];
    if (current == null) return;
    final controller =
        TextEditingController(text: current.totalDays.toStringAsFixed(0));
    final value = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit ${_label(ptoType)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_names[userId] ?? 'Worker'} · $_year',
              style: Theme.of(dialogCtx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Total days',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed < 0) return;
              Navigator.of(dialogCtx).pop(parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    if (!mounted) return;
    final rowKey = '$userId:$ptoType';
    setState(() {
      _saving.add(rowKey);
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ptoRepositoryProvider).upsertAllocation(
            userId: userId,
            ptoType: ptoType,
            year: _year,
            totalDays: value,
          );
      setState(() {
        final slot = _byUser.putIfAbsent(userId, () => {});
        slot[ptoType] = PtoAllocation(
          userId: userId,
          ptoType: ptoType,
          year: _year,
          totalDays: value,
          workerName: current.workerName,
        );
      });
    } on PTORepositoryException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _saving.remove(rowKey));
      }
    }
  }

  String _label(String ptoType) => switch (ptoType) {
        'vacation' => 'Vacation',
        'sick' => 'Sick',
        'personal' => 'Personal',
        _ => ptoType,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final workerIds = _byUser.keys.toList()
      ..sort((a, b) =>
          (_names[a] ?? '').toLowerCase().compareTo((_names[b] ?? '').toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('PTO Allocations'),
        leading: const BackButton(),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Change year',
            onSelected: (y) {
              setState(() => _year = y);
              _load();
            },
            itemBuilder: (_) {
              final now = DateTime.now().toUtc().year;
              return [now - 1, now, now + 1]
                  .map((y) => PopupMenuItem(
                        value: y,
                        child: Row(
                          children: [
                            if (y == _year)
                              const Icon(Icons.check, size: 16)
                            else
                              const SizedBox(width: 16),
                            const SizedBox(width: 8),
                            Text(y.toString()),
                          ],
                        ),
                      ))
                  .toList();
            },
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: SkeletonLoader(itemCount: 6),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: workerIds.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(40),
                          children: [
                            Center(
                              child: Text(
                                'No active workers yet.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: workerIds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final uid = workerIds[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: palette.steel.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _names[uid] ?? 'Worker',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    for (final type in _ptoTypes)
                                      _AllocationRow(
                                        label: _label(type),
                                        value: _byUser[uid]?[type]?.totalDays ?? 0,
                                        saving: _saving.contains('$uid:$type'),
                                        onTap: () => _edit(uid, type),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.label,
    required this.value,
    required this.saving,
    required this.onTap,
  });

  final String label;
  final double value;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: saving ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} days',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 8),
            saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_outlined, size: 16),
          ],
        ),
      ),
    );
  }
}

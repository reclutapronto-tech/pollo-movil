import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantBranchStructureScreen extends ConsumerStatefulWidget {
  const RestaurantBranchStructureScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<RestaurantBranchStructureScreen> createState() =>
      _RestaurantBranchStructureScreenState();
}

class _RestaurantBranchStructureScreenState
    extends ConsumerState<RestaurantBranchStructureScreen> {
  late Future<OpsJson> _structure;
  String? _savingKey;

  @override
  void initState() {
    super.initState();
    _structure = _fetch();
  }

  Future<OpsJson> _fetch() => ref
      .read(restaurantOpsRepositoryProvider)
      .fetchBranchStructure(widget.branchId);

  Future<void> _refresh() async {
    final request = _fetch();
    setState(() => _structure = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the request failure and offers a retry.
    }
  }

  Future<void> _edit({
    required String kind,
    required String label,
    Map<String, dynamic>? row,
    bool? isActive,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _StructureNameDialog(
        title: row == null
            ? l10n.restaurantStructureAdd(label)
            : l10n.restaurantStructureEdit(label),
        initialName: row?['name'] as String? ?? '',
        nameLabel: l10n.restaurantStructureName,
        backLabel: l10n.restaurantStructureBack,
        saveLabel: l10n.restaurantStructureSave,
      ),
    );
    if (name == null || !mounted) return;
    await _persist(
      kind: kind,
      label: label,
      row: row,
      name: name,
      isActive: isActive,
    );
  }

  Future<void> _persist({
    required String kind,
    required String label,
    required String name,
    Map<String, dynamic>? row,
    bool? isActive,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final id = row?['id'] as String?;
    final key = '$kind:${id ?? 'new'}';
    setState(() => _savingKey = key);
    try {
      final repository = ref.read(restaurantOpsRepositoryProvider);
      if (kind == 'area') {
        await repository.saveBranchArea(
          branchId: widget.branchId,
          areaId: id,
          name: name,
          isActive: isActive ?? row?['is_active'] != false,
        );
      } else {
        await repository.saveBranchPosition(
          branchId: widget.branchId,
          positionId: id,
          name: name,
          isActive: isActive ?? row?['is_active'] != false,
        );
      }
      if (!mounted) return;
      setState(() {
        _savingKey = null;
        _structure = _fetch();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantStructureSaved(label))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.restaurantStructureSaveError(label, error.toString()),
          ),
        ),
      );
    }
  }

  Future<void> _setActive({
    required String kind,
    required String label,
    required Map<String, dynamic> row,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final nextActive = row['is_active'] != true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          nextActive
              ? l10n.restaurantStructureReactivateTitle(label)
              : l10n.restaurantStructureDeactivateTitle(label),
        ),
        content: Text(
          nextActive
              ? l10n.restaurantStructureReactivateDescription
              : l10n.restaurantStructureDeactivateDescription,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.restaurantStructureBack),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              nextActive
                  ? l10n.restaurantStructureReactivateAction
                  : l10n.restaurantStructureDeactivateAction,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _persist(
      kind: kind,
      label: label,
      row: row,
      name: row['name'] as String? ?? label,
      isActive: nextActive,
    );
  }

  Widget _section({
    required String kind,
    required String label,
    required List<Map<String, dynamic>> rows,
    required bool readOnly,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.restaurantStructureAddTooltip(label),
                  onPressed: _savingKey == null && !readOnly
                      ? () => _edit(kind: kind, label: label)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l10n.restaurantStructureEmpty),
              ),
            ...rows.map((row) {
              final id = row['id'] as String;
              final busy = _savingKey == '$kind:$id';
              final active = row['is_active'] == true;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row['name'] as String? ?? label),
                subtitle: Text(
                  active
                      ? l10n.restaurantStructureStatusActive
                      : l10n.restaurantStructureStatusInactive,
                ),
                trailing: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        enabled: _savingKey == null && !readOnly,
                        onSelected: (action) {
                          if (action == 'edit') {
                            _edit(kind: kind, label: label, row: row);
                          } else {
                            _setActive(kind: kind, label: label, row: row);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(l10n.restaurantStructureEditName),
                          ),
                          PopupMenuItem(
                            value: 'active',
                            child: Text(
                              active
                                  ? l10n.restaurantStructureDeactivateAction
                                  : l10n.restaurantStructureReactivateAction,
                            ),
                          ),
                        ],
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _clockFeatures(
    Map<String, dynamic> features, {
    required bool readOnly,
  }) => _BranchFeaturesEditor(
    key: ValueKey(
      '${features['enable_time_clock']}:${features['require_gps_for_time_clock']}',
    ),
    branchId: widget.branchId,
    enableTimeClock: features['enable_time_clock'] == true,
    requireGps: features['require_gps_for_time_clock'] == true,
    readOnly: readOnly,
  );

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      _,
      next,
    ) {
      if (next.hasValue && _savingKey == null) _refresh();
    });
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.restaurantStructureTitle)),
      body: FutureBuilder<OpsJson>(
        future: _structure,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.restaurantStructureLoadError),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _structure = _fetch()),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.restaurantStructureRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final areas = (data['areas'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final positions = (data['positions'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final features =
              data['features'] as Map<String, dynamic>? ?? const {};
          final offlineSnapshot = data['_offline_snapshot'] == true;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (offlineSnapshot)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: Icon(Icons.cloud_off_rounded),
                      title: Text(l10n.restaurantStructureOfflineTitle),
                      subtitle: Text(l10n.restaurantStructureOfflineBody),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(l10n.restaurantStructureKeepHistory),
                ),
                _clockFeatures(features, readOnly: offlineSnapshot),
                _section(
                  kind: 'area',
                  label: l10n.restaurantStructureAreas,
                  rows: areas,
                  readOnly: offlineSnapshot,
                ),
                _section(
                  kind: 'position',
                  label: l10n.restaurantStructurePositions,
                  rows: positions,
                  readOnly: offlineSnapshot,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BranchFeaturesEditor extends ConsumerStatefulWidget {
  const _BranchFeaturesEditor({
    super.key,
    required this.branchId,
    required this.enableTimeClock,
    required this.requireGps,
    required this.readOnly,
  });

  final String branchId;
  final bool enableTimeClock;
  final bool requireGps;
  final bool readOnly;

  @override
  ConsumerState<_BranchFeaturesEditor> createState() =>
      _BranchFeaturesEditorState();
}

class _BranchFeaturesEditorState extends ConsumerState<_BranchFeaturesEditor> {
  late bool _enableTimeClock = widget.enableTimeClock;
  late bool _requireGps = widget.enableTimeClock && widget.requireGps;
  late bool _savedTimeClock = _enableTimeClock;
  late bool _savedGps = _requireGps;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _BranchFeaturesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableTimeClock != widget.enableTimeClock ||
        oldWidget.requireGps != widget.requireGps) {
      _enableTimeClock = widget.enableTimeClock;
      _requireGps = widget.enableTimeClock && widget.requireGps;
      _savedTimeClock = _enableTimeClock;
      _savedGps = _requireGps;
    }
  }

  Future<void> _save() async {
    if (_saving ||
        (_enableTimeClock == _savedTimeClock && _requireGps == _savedGps))
      return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .saveBranchFeatures(
            branchId: widget.branchId,
            enableTimeClock: _enableTimeClock,
            requireGps: _requireGps,
          );
      if (!mounted) return;
      setState(() {
        _savedTimeClock = _enableTimeClock;
        _savedGps = _requireGps;
        _saving = false;
      });
      ref.invalidate(restaurantBranchesProvider);
      ref.invalidate(restaurantDashboardProvider(widget.branchId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.restaurantAttendanceSaved)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.restaurantAttendanceSaveError(error.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dirty =
        _enableTimeClock != _savedTimeClock || _requireGps != _savedGps;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.restaurantAttendanceTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.restaurantAttendanceOptional),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.restaurantAttendanceEnableClock),
              subtitle: Text(l10n.restaurantAttendanceClockDescription),
              value: _enableTimeClock,
              onChanged: _saving || widget.readOnly
                  ? null
                  : (value) => setState(() {
                      _enableTimeClock = value;
                      if (!value) _requireGps = false;
                    }),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.restaurantAttendanceRequestGps),
              subtitle: Text(l10n.restaurantAttendanceGpsDescription),
              value: _requireGps,
              onChanged: !_enableTimeClock || _saving || widget.readOnly
                  ? null
                  : (value) => setState(() => _requireGps = value),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: dirty && !_saving && !widget.readOnly ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(l10n.restaurantAttendanceSaveFeatures),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructureNameDialog extends StatefulWidget {
  const _StructureNameDialog({
    required this.title,
    required this.initialName,
    required this.nameLabel,
    required this.backLabel,
    required this.saveLabel,
  });

  final String title;
  final String initialName;
  final String nameLabel;
  final String backLabel;
  final String saveLabel;

  @override
  State<_StructureNameDialog> createState() => _StructureNameDialogState();
}

class _StructureNameDialogState extends State<_StructureNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 100,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(labelText: widget.nameLabel),
      onSubmitted: (_) {
        if (_controller.text.trim().length >= 2) {
          Navigator.pop(context, _controller.text.trim());
        }
      },
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.backLabel),
      ),
      FilledButton(
        onPressed: _controller.text.trim().length < 2
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.saveLabel),
      ),
    ],
  );
}

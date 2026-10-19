import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantAreaInspectionScreen extends ConsumerStatefulWidget {
  const RestaurantAreaInspectionScreen({
    super.key,
    required this.branchId,
    required this.template,
  });

  final String branchId;
  final Map<String, dynamic> template;

  @override
  ConsumerState<RestaurantAreaInspectionScreen> createState() =>
      _RestaurantAreaInspectionScreenState();
}

class _RestaurantAreaInspectionScreenState
    extends ConsumerState<RestaurantAreaInspectionScreen> {
  final _noteController = TextEditingController();
  final Map<String, String?> _results = {};
  final Map<String, String> _itemNotes = {};
  final Map<String, TextEditingController> _itemNoteControllers = {};
  String? _clientEventId;
  bool _saving = false;

  List<Map<String, dynamic>> get _items =>
      (widget.template['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  @override
  void dispose() {
    _noteController.dispose();
    for (final controller in _itemNoteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving ||
        _results.length != _items.length ||
        _results.values.any((value) => value == null)) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      final repository = ref.read(restaurantOpsRepositoryProvider);
      final clientEventId = _clientEventId ?? repository.createClientEventId();
      _clientEventId = clientEventId;
      final result = await repository.recordAreaInspection(
        branchId: widget.branchId,
        templateId: widget.template['id'] as String,
        clientEventId: clientEventId,
        note: _noteController.text.trim(),
        results: _items
            .map((item) {
              final itemId = item['id'] as String;
              return <String, dynamic>{
                'item_id': itemId,
                'result_state': _results[itemId]!,
                if ((_itemNotes[itemId] ?? '').trim().isNotEmpty)
                  'note': _itemNotes[itemId]!.trim(),
              };
            })
            .toList(growable: false),
      );
      if (!mounted) return;
      final count = (result['needs_attention_count'] as num? ?? 0).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['queued'] == true
                ? l10n.restaurantInspectionQueued
                : count == 0
                ? l10n.restaurantInspectionSaved
                : l10n.restaurantInspectionNeedsAttention(count),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final templateName =
        widget.template['name'] as String? ??
        l10n.restaurantInspectionDefaultTitle;
    return Scaffold(
      appBar: AppBar(title: Text(templateName)),
      body: _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.restaurantInspectionNoActiveCriteria,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (widget.template['area_name'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      widget.template['area_name'] as String,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                Text(
                  l10n.restaurantInspectionInstruction,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ..._items.map((item) {
                  final id = item['id'] as String;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['label'] as String? ??
                                l10n.restaurantInspectionCriterion,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _results[id],
                            decoration: InputDecoration(
                              labelText: l10n.restaurantInspectionObservedState,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'ok',
                                child: Text(l10n.restaurantInspectionResultOk),
                              ),
                              DropdownMenuItem(
                                value: 'needs_attention',
                                child: Text(
                                  l10n.restaurantInspectionResultNeedsAttention,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'not_applicable',
                                child: Text(
                                  l10n.restaurantInspectionResultNotApplicable,
                                ),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() {
                                    _results[id] = value;
                                    _clientEventId = null;
                                    if (value != 'needs_attention') {
                                      _itemNotes.remove(id);
                                      _itemNoteControllers[id]?.clear();
                                    }
                                  }),
                          ),
                          if (_results[id] == 'needs_attention') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _itemNoteControllers.putIfAbsent(
                                id,
                                TextEditingController.new,
                              ),
                              maxLength: 500,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText:
                                    l10n.restaurantInspectionOptionalDetail,
                                alignLabelWithHint: true,
                              ),
                              onChanged: (value) {
                                _itemNotes[id] = value;
                                _clientEventId = null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                TextField(
                  controller: _noteController,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.restaurantInspectionOptionalGeneralNote,
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => _clientEventId = null,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed:
                        _saving ||
                            _results.length != _items.length ||
                            _results.values.any((value) => value == null)
                        ? null
                        : _submit,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      _saving
                          ? l10n.restaurantInspectionSaving
                          : l10n.restaurantInspectionSave,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.restaurantInspectionOfflineHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

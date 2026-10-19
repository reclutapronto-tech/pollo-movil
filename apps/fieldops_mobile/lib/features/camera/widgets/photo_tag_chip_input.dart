import 'dart:async';

import 'package:fieldops_mobile/features/camera/data/photo_tags_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tag-chip input for the post-capture review flow.
///
/// Shows current tags as dismissible chips. Typing surfaces frequency-ranked
/// suggestions from [PhotoTagsRepository.suggest]. Emits the current tag list
/// via [onChanged] so callers can persist via [PhotoTagsRepository.attachTag]
/// once a `media_asset_id` is assigned.
class PhotoTagChipInput extends ConsumerStatefulWidget {
  const PhotoTagChipInput({
    required this.tags,
    required this.onChanged,
    this.maxTags = 12,
    super.key,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final int maxTags;

  @override
  ConsumerState<PhotoTagChipInput> createState() => _PhotoTagChipInputState();
}

class _PhotoTagChipInputState extends ConsumerState<PhotoTagChipInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<TagSuggestion> _suggestions = const [];
  bool _isLoading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleSuggest(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final repo = ref.read(photoTagsRepositoryProvider);
    final results = await repo.suggest(query: query);
    if (!mounted) return;
    setState(() {
      _suggestions = results
          .where((s) => !widget.tags.any((t) => t.toLowerCase() == s.tag.toLowerCase()))
          .toList();
      _isLoading = false;
    });
  }

  void _addTag(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    if (widget.tags.length >= widget.maxTags) return;
    if (widget.tags.any((t) => t.toLowerCase() == trimmed.toLowerCase())) return;
    final next = [...widget.tags, trimmed];
    widget.onChanged(next);
    _controller.clear();
    setState(() => _suggestions = const []);
  }

  void _removeTag(String tag) {
    widget.onChanged(widget.tags.where((t) => t != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => _removeTag(tag),
                ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Add tag (e.g. roof, damage, before)',
            prefixIcon: const Icon(Icons.label_outline),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: _scheduleSuggest,
          onSubmitted: _addTag,
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _suggestions.take(8))
                ActionChip(
                  label: Text('${s.tag} · ${s.count}'),
                  onPressed: () => _addTag(s.tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

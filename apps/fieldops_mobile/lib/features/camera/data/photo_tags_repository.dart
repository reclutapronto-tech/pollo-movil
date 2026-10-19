import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Client for the `tags` edge function. Attaches and removes free-form photo
/// tags; returns frequency-ranked suggestions for the tag-chip input.
class PhotoTagsRepository {
  PhotoTagsRepository(this._client, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  Future<void> attachTag({
    required List<String> mediaAssetIds,
    required String tag,
  }) async {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || mediaAssetIds.isEmpty) return;
    try {
      await _client.functions.invoke(
        'tags',
        method: HttpMethod.post,
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'media_asset_ids': mediaAssetIds,
          'tag': trimmed,
        },
      );
    } on SocketException {
      throw const PhotoTagsException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const PhotoTagsException.offline();
      throw PhotoTagsException.unknown('Tag request failed (${error.status}).');
    }
  }

  Future<void> removeTag({
    required String mediaAssetId,
    required String tag,
  }) async {
    try {
      await _client.functions.invoke(
        'tags',
        method: HttpMethod.delete,
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {'media_asset_id': mediaAssetId, 'tag': tag.trim()},
      );
    } on SocketException {
      throw const PhotoTagsException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) throw const PhotoTagsException.offline();
      throw PhotoTagsException.unknown('Tag removal failed (${error.status}).');
    }
  }

  Future<List<TagSuggestion>> suggest({String? query}) async {
    try {
      final response = await _client.functions.invoke(
        'tags',
        method: HttpMethod.get,
        headers: {'X-Client-Version': 'fieldops-mobile'},
        queryParameters: {
          if (query != null && query.isNotEmpty) 'q': query,
          'path': '/suggest', // documented path; the function branches on suffix
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final rows = data['suggestions'] as List<dynamic>? ?? const [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map((r) => TagSuggestion(
                tag: r['tag'] as String? ?? '',
                count: (r['count'] as num?)?.toInt() ?? 0,
              ))
          .where((s) => s.tag.isNotEmpty)
          .toList();
    } on SocketException {
      return const [];
    } on FunctionException {
      return const [];
    }
  }
}

class TagSuggestion {
  const TagSuggestion({required this.tag, required this.count});
  final String tag;
  final int count;
}

enum PhotoTagsErrorType { offline, unknown }

class PhotoTagsException implements Exception {
  const PhotoTagsException._({required this.type, required this.message});

  const PhotoTagsException.offline()
      : this._(
          type: PhotoTagsErrorType.offline,
          message: 'Tag will sync when connection returns.',
        );

  const PhotoTagsException.unknown([
    String message = 'Tag could not be saved right now.',
  ]) : this._(type: PhotoTagsErrorType.unknown, message: message);

  final PhotoTagsErrorType type;
  final String message;

  @override
  String toString() => 'PhotoTagsException($type): $message';
}

final photoTagsRepositoryProvider = Provider<PhotoTagsRepository>((ref) {
  return PhotoTagsRepository(Supabase.instance.client);
});

import 'dart:io';
import 'dart:typed_data';

import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseMediaRepository implements MediaRepository {
  SupabaseMediaRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<PresignResult> presignUpload({
    required String jobId,
    required String mimeType,
    required int fileSizeBytes,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'media_presign',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'job_id': jobId,
          'mime_type': mimeType,
          'file_size_bytes': fileSizeBytes,
        },
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const MediaRepositoryException.unknown(
          'Presign response was malformed.',
        );
      }

      final uploadUrl = payload['upload_url'] as String?;
      final mediaAssetId = payload['media_asset_id'] as String?;

      if (uploadUrl == null || mediaAssetId == null) {
        throw const MediaRepositoryException.unknown(
          'Presign response missing required fields.',
        );
      }

      return PresignResult(
        uploadUrl: uploadUrl,
        mediaAssetId: mediaAssetId,
      );
    } on SocketException {
      throw const MediaRepositoryException.offline();
    } on HttpException {
      throw const MediaRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const MediaRepositoryException.offline();
      }
      throw MediaRepositoryException.unknown(
        'Presign request failed (${error.status}).',
      );
    }
  }

  @override
  Future<void> uploadFile({
    required String uploadUrl,
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    try {
      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': mimeType},
        body: fileBytes,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MediaRepositoryException.uploadFailed(
          'Upload returned status ${response.statusCode}.',
        );
      }
    } on SocketException {
      throw const MediaRepositoryException.offline();
    } on HttpException {
      throw const MediaRepositoryException.offline();
    }
  }

  @override
  Future<void> finalizeUpload({required String mediaAssetId}) async {
    try {
      final response = await _client.functions.invoke(
        'media_finalize',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {'media_asset_id': mediaAssetId},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const MediaRepositoryException.unknown(
          'Finalize response was malformed.',
        );
      }
    } on SocketException {
      throw const MediaRepositoryException.offline();
    } on HttpException {
      throw const MediaRepositoryException.offline();
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const MediaRepositoryException.offline();
      }
      throw MediaRepositoryException.unknown(
        'Finalize request failed (${error.status}).',
      );
    }
  }
}

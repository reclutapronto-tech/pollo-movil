import 'dart:typed_data';

class PresignResult {
  const PresignResult({
    required this.uploadUrl,
    required this.mediaAssetId,
  });

  final String uploadUrl;
  final String mediaAssetId;
}

abstract class MediaRepository {
  Future<PresignResult> presignUpload({
    required String jobId,
    required String mimeType,
    required int fileSizeBytes,
  });

  Future<void> uploadFile({
    required String uploadUrl,
    required Uint8List fileBytes,
    required String mimeType,
  });

  Future<void> finalizeUpload({required String mediaAssetId});
}

enum MediaRepositoryErrorType { offline, uploadFailed, unknown }

class MediaRepositoryException implements Exception {
  const MediaRepositoryException._({
    required this.type,
    required this.message,
  });

  const MediaRepositoryException.offline()
      : this._(
          type: MediaRepositoryErrorType.offline,
          message: 'No connection available for photo upload.',
        );

  const MediaRepositoryException.uploadFailed([
    String message = 'Photo upload failed. Try again.',
  ]) : this._(type: MediaRepositoryErrorType.uploadFailed, message: message);

  const MediaRepositoryException.unknown([
    String message = 'Photo could not be processed right now.',
  ]) : this._(type: MediaRepositoryErrorType.unknown, message: message);

  final MediaRepositoryErrorType type;
  final String message;

  @override
  String toString() => 'MediaRepositoryException($type): $message';
}

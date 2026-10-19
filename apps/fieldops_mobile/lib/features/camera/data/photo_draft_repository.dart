import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/camera/data/exif_stripper.dart';
import 'package:fieldops_mobile/features/camera/data/media_repository_provider.dart';
import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class PhotoDraftRepository {
  PhotoDraftRepository({
    required LocalDatabase database,
    required MediaRepository mediaRepository,
    Uuid? uuid,
  }) : _database = database,
       _mediaRepository = mediaRepository,
       _uuid = uuid ?? const Uuid();

  final LocalDatabase _database;
  final MediaRepository _mediaRepository;
  final Uuid _uuid;

  Stream<List<PendingMediaUpload>> watchDraftsForJob(String jobId) {
    return _database.watchPendingMediaUploadsForJob(jobId);
  }

  Future<int> draftCount({String? jobId}) {
    return _database.pendingMediaUploadCount(jobId: jobId);
  }

  Stream<int> watchDraftCount({String? jobId}) {
    return _database.watchPendingMediaUploadCount(jobId: jobId);
  }

  Future<String> saveDraft({
    required String jobId,
    required String filePath,
    String mimeType = 'image/jpeg',
  }) async {
    final draftId = _uuid.v4();
    await _database.savePendingMediaUpload(
      PendingMediaUploadsCompanion.insert(
        id: draftId,
        jobId: jobId,
        filePath: filePath,
        mimeType: Value(mimeType),
      ),
    );
    return draftId;
  }

  Future<void> deleteDraft(String draftId) async {
    final draft = await _database.findPendingMediaUpload(draftId);
    if (draft == null) return;

    await _database.deletePendingMediaUpload(draftId);

    final file = File(draft.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> uploadDraft(String draftId) async {
    final draft = await _database.findPendingMediaUpload(draftId);
    if (draft == null) {
      throw const MediaRepositoryException.unknown(
        'Saved photo could not be found.',
      );
    }

    final file = File(draft.filePath);
    if (!await file.exists()) {
      await _database.deletePendingMediaUpload(draftId);
      throw const MediaRepositoryException.unknown(
        'Saved photo file is missing.',
      );
    }

    // Strip EXIF metadata (GPS, timestamps, device info) before upload.
    // The direct-upload path strips EXIF via proof stamp decode→encode,
    // but drafts bypass that — so we strip explicitly here.
    const exifStripper = ExifStripper();
    final rawBytes = await file.readAsBytes();
    final fileBytes = exifStripper.stripBytes(rawBytes);

    try {
      final presign = await _mediaRepository.presignUpload(
        jobId: draft.jobId,
        mimeType: draft.mimeType,
        fileSizeBytes: fileBytes.length,
      );

      await _mediaRepository.uploadFile(
        uploadUrl: presign.uploadUrl,
        fileBytes: fileBytes,
        mimeType: draft.mimeType,
      );

      await _mediaRepository.finalizeUpload(mediaAssetId: presign.mediaAssetId);

      // Mark uploaded first — if deleteDraft fails or app crashes after this
      // point, the "uploaded" flag prevents a duplicate re-upload on next launch.
      await _database.markPendingMediaUploadUploaded(draftId);

      // Best-effort cleanup of the local file and DB record. If this fails
      // (e.g. app crash), the file is orphaned but the upload is safe.
      try {
        await deleteDraft(draftId);
      } on Exception catch (_) {
        // Orphaned file — will be cleaned up by periodic maintenance.
      }

      return presign.mediaAssetId;
    } on MediaRepositoryException catch (error) {
      await _database.markPendingMediaUploadFailed(
        draftId,
        error.message,
        retryCount: draft.retryCount + 1,
      );
      rethrow;
    }
  }
}

final photoDraftRepositoryProvider = Provider<PhotoDraftRepository>((ref) {
  return PhotoDraftRepository(
    database: ref.watch(localDatabaseProvider),
    mediaRepository: ref.watch(mediaRepositoryProvider),
  );
});

final pendingPhotoDraftCountProvider = StreamProvider<int>((ref) {
  return ref.watch(photoDraftRepositoryProvider).watchDraftCount();
});

final pendingPhotoDraftCountForJobProvider = StreamProvider.family<int, String>(
  (ref, jobId) {
    return ref
        .watch(photoDraftRepositoryProvider)
        .watchDraftCount(jobId: jobId);
  },
);

final photoDraftsForJobProvider =
    StreamProvider.family<List<PendingMediaUpload>, String>((ref, jobId) {
      return ref.watch(photoDraftRepositoryProvider).watchDraftsForJob(jobId);
    });

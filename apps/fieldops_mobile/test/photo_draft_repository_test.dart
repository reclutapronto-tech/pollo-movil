import 'package:drift/native.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves and counts photo drafts by job', () async {
    final database = LocalDatabase.forTesting(NativeDatabase.memory());
    final repository = PhotoDraftRepository(
      database: database,
      mediaRepository: _FakeMediaRepository(),
    );

    await repository.saveDraft(jobId: 'job-1', filePath: '/tmp/photo-a.jpg');
    await repository.saveDraft(jobId: 'job-1', filePath: '/tmp/photo-b.jpg');
    await repository.saveDraft(jobId: 'job-2', filePath: '/tmp/photo-c.jpg');

    expect(await repository.draftCount(), 3);
    expect(await repository.draftCount(jobId: 'job-1'), 2);
    expect(await repository.draftCount(jobId: 'job-2'), 1);

    await database.close();
  });
}

class _FakeMediaRepository implements MediaRepository {
  @override
  Future<void> finalizeUpload({required String mediaAssetId}) async {}

  @override
  Future<PresignResult> presignUpload({
    required String jobId,
    required String mimeType,
    required int fileSizeBytes,
  }) async {
    return const PresignResult(
      uploadUrl: 'https://example.com/upload',
      mediaAssetId: 'media-1',
    );
  }

  @override
  Future<void> uploadFile({
    required String uploadUrl,
    required fileBytes,
    required String mimeType,
  }) async {}
}

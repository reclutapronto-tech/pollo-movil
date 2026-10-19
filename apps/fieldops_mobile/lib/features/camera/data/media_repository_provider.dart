import 'dart:typed_data';

import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/camera/data/supabase_media_repository.dart';
import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const _UnconfiguredMediaRepository();
  }

  return SupabaseMediaRepository(Supabase.instance.client);
});

class _UnconfiguredMediaRepository implements MediaRepository {
  const _UnconfiguredMediaRepository();

  @override
  Future<PresignResult> presignUpload({
    required String jobId,
    required String mimeType,
    required int fileSizeBytes,
  }) {
    throw const MediaRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<void> uploadFile({
    required String uploadUrl,
    required Uint8List fileBytes,
    required String mimeType,
  }) {
    throw const MediaRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }

  @override
  Future<void> finalizeUpload({required String mediaAssetId}) {
    throw const MediaRepositoryException.unknown(
      'Mobile app is missing Supabase configuration.',
    );
  }
}

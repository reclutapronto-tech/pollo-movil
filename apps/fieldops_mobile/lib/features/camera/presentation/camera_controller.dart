import 'dart:io';

import 'package:camera/camera.dart' as cam;
import 'package:fieldops_mobile/features/camera/data/exif_stripper.dart';
import 'package:fieldops_mobile/features/camera/data/media_repository_provider.dart';
import 'package:fieldops_mobile/features/camera/data/proof_stamp_renderer.dart';
import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureState>(CaptureController.new);

class CaptureController extends Notifier<CaptureState> {
  @override
  CaptureState build() => const CaptureIdle();

  Future<String> uploadCapturedPhoto({
    required String jobId,
    required String filePath,
    ProofStampMetadata? stampMetadata,
  }) async {
    try {
      state = const CaptureUploading();

      // Apply proof stamp before reading final bytes.
      // Proof stamp decode→encode cycle also strips EXIF metadata.
      if (stampMetadata != null) {
        const renderer = ProofStampRenderer();
        await renderer.stampFile(filePath, stampMetadata);
      } else {
        // No stamp — still strip EXIF to prevent GPS/timestamp leaks.
        const exifStripper = ExifStripper();
        await exifStripper.stripFile(filePath);
      }

      final file = File(filePath);
      final fileBytes = await file.readAsBytes();
      final fileSizeBytes = fileBytes.length;

      final repository = ref.read(mediaRepositoryProvider);

      final presign = await repository.presignUpload(
        jobId: jobId,
        mimeType: 'image/jpeg',
        fileSizeBytes: fileSizeBytes,
      );

      await repository.uploadFile(
        uploadUrl: presign.uploadUrl,
        fileBytes: fileBytes,
        mimeType: 'image/jpeg',
      );

      state = const CaptureFinalizing();

      await repository.finalizeUpload(mediaAssetId: presign.mediaAssetId);

      state = CaptureDone(mediaAssetId: presign.mediaAssetId);
      return presign.mediaAssetId;
    } on MediaRepositoryException catch (error) {
      state = CaptureError(message: error.message);
      rethrow;
    } on cam.CameraException catch (error) {
      state = CaptureError(
        message: error.description ?? 'Camera capture failed.',
      );
      throw const MediaRepositoryException.unknown('Camera capture failed.');
    } on Exception catch (_) {
      state = const CaptureError(
        message: 'Photo capture could not be completed.',
      );
      throw const MediaRepositoryException.unknown();
    }
  }

  void reset() {
    state = const CaptureIdle();
  }
}

sealed class CaptureState {
  const CaptureState();
}

class CaptureIdle extends CaptureState {
  const CaptureIdle();
}

class CaptureCapturing extends CaptureState {
  const CaptureCapturing();
}

class CaptureUploading extends CaptureState {
  const CaptureUploading();
}

class CaptureFinalizing extends CaptureState {
  const CaptureFinalizing();
}

class CaptureDone extends CaptureState {
  const CaptureDone({required this.mediaAssetId});
  final String mediaAssetId;
}

class CaptureError extends CaptureState {
  const CaptureError({required this.message});
  final String message;
}

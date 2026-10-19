import 'dart:io';

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/auth/presentation/session_controller.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/camera/data/photo_enhancer.dart';
import 'package:fieldops_mobile/features/camera/data/photo_tags_repository.dart';
import 'package:fieldops_mobile/features/camera/data/proof_stamp_renderer.dart';
import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_controller.dart';
import 'package:fieldops_mobile/features/camera/presentation/photo_annotation_screen.dart';
import 'package:fieldops_mobile/features/camera/widgets/photo_tag_chip_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class PhotoReviewScreen extends ConsumerStatefulWidget {
  const PhotoReviewScreen({
    super.key,
    required this.jobId,
    required this.jobName,
    required this.filePath,
    this.allowSaveForLater = false,
  });

  final String jobId;
  final String jobName;
  final String filePath;
  final bool allowSaveForLater;

  @override
  ConsumerState<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends ConsumerState<PhotoReviewScreen> {
  final _photoEnhancer = const PhotoEnhancer();
  bool _isEnhancing = false;
  bool _isStamping = false;
  bool _enhanced = false;
  bool _annotated = false;
  int _previewRevision = 0;

  /// Tracks the current file path — may differ from widget.filePath after
  /// annotation bakes a new composite PNG to a temp file.
  late String _currentFilePath;

  /// User-entered tags to attach after upload. Tags need a real media_asset_id
  /// so attachment runs post-finalize.
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.filePath;
  }

  Future<void> _annotate() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PhotoAnnotationScreen(filePath: _currentFilePath),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _currentFilePath = result;
        _annotated = true;
        _previewRevision += 1;
      });
    }
  }

  Future<void> _autoEnhance() async {
    if (_isEnhancing) return;

    setState(() => _isEnhancing = true);

    try {
      await _photoEnhancer.autoEnhanceFile(_currentFilePath);
      if (!mounted) return;
      setState(() {
        _enhanced = true;
        _previewRevision += 1;
      });
    } on PhotoEnhancerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _isEnhancing = false);
      }
    }
  }

  Future<void> _saveForLater() async {
    final draftId = await ref
        .read(photoDraftRepositoryProvider)
        .saveDraft(jobId: widget.jobId, filePath: _currentFilePath);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(PhotoCaptureResult.savedForLater(draftId: draftId));
  }

  Future<ProofStampMetadata> _buildStampMetadata() async {
    final session = ref.read(sessionControllerProvider);
    final workerEmail = session.email ?? 'unknown';

    double? lat;
    double? lng;
    double? accuracy;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));
      lat = position.latitude;
      lng = position.longitude;
      accuracy = position.accuracy;
    } on Exception catch (_) {
      // GPS unavailable — stamp without coordinates
    }

    return ProofStampMetadata(
      workerEmail: workerEmail,
      jobName: widget.jobName,
      capturedAt: DateTime.now().toUtc(),
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
    );
  }

  Future<void> _uploadNow() async {
    if (_isStamping) return;
    setState(() => _isStamping = true);

    try {
      final stampMetadata = await _buildStampMetadata();

      final mediaAssetId = await ref
          .read(captureControllerProvider.notifier)
          .uploadCapturedPhoto(
            jobId: widget.jobId,
            filePath: _currentFilePath,
            stampMetadata: stampMetadata,
          );

      // Attach any user-entered tags. Failures must not block upload success —
      // a field worker who tagged offline should still see the photo shipped.
      if (_tags.isNotEmpty) {
        final tagsRepo = ref.read(photoTagsRepositoryProvider);
        for (final tag in _tags) {
          try {
            await tagsRepo.attachTag(
              mediaAssetIds: [mediaAssetId],
              tag: tag,
            );
          } on PhotoTagsException catch (e) {
            debugPrint('[review] tag "$tag" deferred: ${e.message}');
          }
        }
      }

      // Clean up the temp photo file after successful upload to prevent
      // orphaned files accumulating on disk.
      try {
        final tempFile = File(_currentFilePath);
        if (await tempFile.exists()) await tempFile.delete();
      } on FileSystemException catch (_) {
        // Best-effort cleanup — don't block success path.
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(PhotoCaptureResult.uploaded(mediaAssetId: mediaAssetId));
    } on MediaRepositoryException {
      // UI state already updated by the capture controller.
    } finally {
      if (mounted) {
        setState(() => _isStamping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final captureState = ref.watch(captureControllerProvider);
    final hasUploadError = captureState is CaptureError;
    final isBusy =
        _isEnhancing ||
        _isStamping ||
        captureState is CaptureUploading ||
        captureState is CaptureFinalizing;

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: const Text('Review photo'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(FieldOpsSpacing.base),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_currentFilePath),
                        key: ValueKey('review-photo-$_previewRevision'),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, _) {
                          return ColoredBox(
                            color: Colors.black54,
                            child: Center(
                              child: Text(
                                'Photo preview unavailable',
                                style: textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        left: 16,
                        top: 16,
                        child: _ReviewChip(
                          icon: Icons.work_outline_rounded,
                          label: widget.jobName,
                        ),
                      ),
                      const Positioned(
                        left: 16,
                        bottom: 16,
                        child: _ReviewChip(
                          icon: Icons.verified_user_rounded,
                          label: 'Proof stamp will be applied',
                        ),
                      ),
                      if (_enhanced)
                        const Positioned(
                          right: 16,
                          top: 16,
                          child: _ReviewChip(
                            icon: Icons.auto_fix_high_rounded,
                            label: 'Enhanced',
                          ),
                        ),
                      if (_annotated)
                        const Positioned(
                          right: 16,
                          bottom: 16,
                          child: _ReviewChip(
                            icon: Icons.brush_rounded,
                            label: 'Annotated',
                          ),
                        ),
                      if (isBusy)
                        Container(
                          color: Colors.black45,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isEnhancing
                                    ? 'Enhancing photo...'
                                    : captureState is CaptureFinalizing
                                    ? 'Finalizing upload...'
                                    : captureState is CaptureUploading
                                    ? 'Uploading photo...'
                                    : _isStamping
                                    ? 'Applying proof stamp...'
                                    : 'Processing...',
                                style: textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (captureState is CaptureError)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FieldOpsSpacing.base,
                ),
                child: Container(
                  padding: const EdgeInsets.all(FieldOpsSpacing.base),
                  decoration: BoxDecoration(
                    color: palette.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
                    border: Border.all(
                      color: palette.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    captureState.message,
                    style: textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FieldOpsSpacing.base,
                FieldOpsSpacing.base,
                FieldOpsSpacing.base,
                FieldOpsSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Timestamp, GPS & worker ID will be stamped before upload.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.86),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tag chips — attached after the photo finalizes upload.
                  PhotoTagChipInput(
                    tags: _tags,
                    onChanged: (next) => setState(() => _tags = next),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => Navigator.of(
                                  context,
                                ).pop(const PhotoCaptureResult.retake()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            minimumSize: const Size.fromHeight(54),
                          ),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('Retake'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusy ? null : _annotate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(
                              color: Color(0x6638BDF8),
                            ),
                            minimumSize: const Size.fromHeight(54),
                          ),
                          icon: const Icon(Icons.brush_rounded),
                          label: Text(_annotated ? 'Annotated' : 'Annotate'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusy ? null : _autoEnhance,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.signal,
                            side: BorderSide(
                              color: palette.signal.withValues(alpha: 0.45),
                            ),
                            minimumSize: const Size.fromHeight(54),
                          ),
                          icon: const Icon(Icons.auto_fix_high_rounded),
                          label: Text(_enhanced ? 'Enhanced' : 'Enhance'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.allowSaveForLater) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isBusy ? null : _saveForLater,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              minimumSize: const Size.fromHeight(54),
                            ),
                            icon: const Icon(Icons.download_done_rounded),
                            label: const Text('Save for later'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isBusy ? null : _uploadNow,
                            icon: Icon(
                              hasUploadError
                                  ? Icons.refresh_rounded
                                  : Icons.cloud_upload_rounded,
                            ),
                            label: Text(
                              hasUploadError ? 'Retry' : 'Upload now',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : _uploadNow,
                        icon: Icon(
                          hasUploadError
                              ? Icons.refresh_rounded
                              : Icons.cloud_upload_rounded,
                        ),
                        label: Text(
                          hasUploadError ? 'Retry upload' : 'Use this photo',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewChip extends StatelessWidget {
  const _ReviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(FieldOpsRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

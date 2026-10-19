import 'package:camera/camera.dart' as cam;
import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/camera/domain/photo_capture_result.dart';
import 'package:fieldops_mobile/features/camera/presentation/camera_controller.dart';
import 'package:fieldops_mobile/features/camera/presentation/photo_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Photo mode for before/after pairing.
enum PhotoMode { standard, before, after }

class CameraCaptureScreen extends ConsumerStatefulWidget {
  const CameraCaptureScreen({
    super.key,
    required this.jobId,
    required this.jobName,
    this.photoMode = PhotoMode.standard,
    this.beforeAfterGroupId,
    this.allowSaveForLater = false,
  });

  final String jobId;
  final String jobName;
  final PhotoMode photoMode;
  final String? beforeAfterGroupId;
  final bool allowSaveForLater;

  @override
  ConsumerState<CameraCaptureScreen> createState() =>
      _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen> {
  cam.CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _disposed = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await cam.availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found on this device.');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = cam.CameraController(
        backCamera,
        cam.ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: cam.ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
      });
    } on cam.CameraException catch (e) {
      setState(
        () => _cameraError = e.description ?? 'Camera initialization failed.',
      );
    } on Exception catch (_) {
      setState(() => _cameraError = 'Could not start camera.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _disposed) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final xFile = await controller.takePicture();
      if (!mounted || _disposed) return;

      final result = await Navigator.of(context).push<PhotoCaptureResult>(
        MaterialPageRoute<PhotoCaptureResult>(
          builder: (_) => PhotoReviewScreen(
            jobId: widget.jobId,
            jobName: widget.jobName,
            filePath: xFile.path,
            allowSaveForLater: widget.allowSaveForLater,
          ),
        ),
      );

      if (!mounted || _disposed || result == null) return;

      if (result.shouldRetake) {
        return;
      }

      ref.read(captureControllerProvider.notifier).reset();
      Navigator.of(context).pop(result);
    } on cam.CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.description ?? 'Photo capture could not be completed.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final captureState = ref.watch(captureControllerProvider);
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview or placeholder
            if (_cameraError != null)
              _CameraErrorView(
                message: _cameraError!,
                onBack: () => Navigator.of(context).pop(),
              )
            else if (!_isCameraReady)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else
              cam.CameraPreview(_cameraController!),

            // Top bar with job name and close button
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Close camera',
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.photoMode == PhotoMode.before
                                ? 'BEFORE photo'
                                : widget.photoMode == PhotoMode.after
                                ? 'AFTER photo'
                                : 'Proof photo',
                            style: textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            widget.jobName,
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: _buildBottomContent(captureState, palette, textTheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomContent(
    CaptureState captureState,
    FieldOpsPalette palette,
    TextTheme textTheme,
  ) {
    return switch (captureState) {
      CaptureIdle() => _CaptureButton(
        onCapture: _capture,
        isCapturing: _isCapturing,
      ),
      CaptureCapturing() => _CaptureButton(
        onCapture: _capture,
        isCapturing: true,
      ),
      CaptureUploading() => _StatusIndicator(
        icon: Icons.cloud_upload_rounded,
        label: 'Uploading proof photo...',
        color: palette.signal,
      ),
      CaptureFinalizing() => _StatusIndicator(
        icon: Icons.verified_rounded,
        label: 'Finalizing...',
        color: palette.signal,
      ),
      CaptureDone() => _StatusIndicator(
        icon: Icons.check_circle_rounded,
        label: 'Photo uploaded successfully',
        color: palette.success,
      ),
      CaptureError(message: final msg) => _ErrorControls(
        message: msg,
        palette: palette,
        onRetry: _capture,
        onCancel: () => Navigator.of(context).pop(),
      ),
    };
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onCapture, required this.isCapturing});

  final VoidCallback onCapture;
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isCapturing ? 'Capturing photo...' : 'Tap to capture proof photo',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: 'Capture photo',
          child: GestureDetector(
            onTap: isCapturing ? null : onCapture,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorControls extends StatelessWidget {
  const _ErrorControls({
    required this.message,
    required this.palette,
    required this.onRetry,
    required this.onCancel,
  });

  final String message;
  final FieldOpsPalette palette;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      liveRegion: true,
      label: 'Error: $message',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: palette.danger, size: 40),
          const SizedBox(height: 10),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: textTheme.titleLarge?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onBack, child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}

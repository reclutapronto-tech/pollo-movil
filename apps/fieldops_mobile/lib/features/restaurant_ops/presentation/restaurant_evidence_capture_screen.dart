import 'package:camera/camera.dart' as camera;
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class RestaurantEvidenceCaptureScreen extends StatefulWidget {
  const RestaurantEvidenceCaptureScreen({super.key});

  @override
  State<RestaurantEvidenceCaptureScreen> createState() =>
      _RestaurantEvidenceCaptureScreenState();
}

class _RestaurantEvidenceCaptureScreenState
    extends State<RestaurantEvidenceCaptureScreen> {
  camera.CameraController? _controller;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await camera.availableCameras();
      if (cameras.isEmpty) throw StateError('No camera available.');
      final device = cameras.firstWhere(
        (item) => item.lensDirection == camera.CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = camera.CameraController(
        device,
        camera.ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: camera.ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on Object catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(
            context,
          )!.restaurantEvidenceCameraOpenError,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !controller.value.isInitialized) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(photo.path);
    } on Object catch (_) {
      if (mounted) {
        setState(() => _error = l10n.restaurantEvidencePhotoSaveError);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.restaurantEvidenceTitle),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                  : controller == null || !controller.value.isInitialized
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : Center(child: camera.CameraPreview(controller)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: controller == null || _capturing ? null : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _capturing
                        ? l10n.restaurantEvidenceSaving
                        : l10n.restaurantEvidenceTakePhoto,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

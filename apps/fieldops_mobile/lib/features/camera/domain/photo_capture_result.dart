enum PhotoCaptureResultType { uploaded, savedForLater, retake }

class PhotoCaptureResult {
  const PhotoCaptureResult._({
    required this.type,
    this.mediaAssetId,
    this.draftId,
  });

  const PhotoCaptureResult.uploaded({required String mediaAssetId})
    : this._(type: PhotoCaptureResultType.uploaded, mediaAssetId: mediaAssetId);

  const PhotoCaptureResult.savedForLater({required String draftId})
    : this._(type: PhotoCaptureResultType.savedForLater, draftId: draftId);

  const PhotoCaptureResult.retake()
    : this._(type: PhotoCaptureResultType.retake);

  final PhotoCaptureResultType type;
  final String? mediaAssetId;
  final String? draftId;

  bool get isUploaded => type == PhotoCaptureResultType.uploaded;
  bool get isSavedForLater => type == PhotoCaptureResultType.savedForLater;
  bool get shouldRetake => type == PhotoCaptureResultType.retake;
}

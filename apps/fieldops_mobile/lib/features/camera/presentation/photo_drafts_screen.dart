import 'dart:io';

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/camera/data/photo_draft_repository.dart';
import 'package:fieldops_mobile/features/camera/domain/media_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PhotoDraftsScreen extends ConsumerStatefulWidget {
  const PhotoDraftsScreen({
    super.key,
    required this.jobId,
    required this.jobName,
  });

  final String jobId;
  final String jobName;

  @override
  ConsumerState<PhotoDraftsScreen> createState() => _PhotoDraftsScreenState();
}

class _PhotoDraftsScreenState extends ConsumerState<PhotoDraftsScreen> {
  String? _uploadingDraftId;

  Future<void> _sendDraft(PendingMediaUpload draft) async {
    setState(() => _uploadingDraftId = draft.id);
    try {
      await ref.read(photoDraftRepositoryProvider).uploadDraft(draft.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved photo sent')));
    } on MediaRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _uploadingDraftId = null);
      }
    }
  }

  Future<void> _deleteDraft(PendingMediaUpload draft) {
    return ref.read(photoDraftRepositoryProvider).deleteDraft(draft.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final draftsAsync = ref.watch(photoDraftsForJobProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(title: const Text('Saved photos')),
      body: draftsAsync.when(
        data: (drafts) {
          if (drafts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(FieldOpsSpacing.xl),
                child: Text(
                  'No saved photos for ${widget.jobName} yet.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(FieldOpsSpacing.base),
            itemCount: drafts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final draft = drafts[index];
              final isUploading = _uploadingDraftId == draft.id;

              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(
                        File(draft.filePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: palette.muted,
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded, size: 40),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(FieldOpsSpacing.base),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saved ${_timeLabel(draft.createdAt)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (draft.errorMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              draft.errorMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.danger),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isUploading
                                      ? null
                                      : () => _deleteDraft(draft),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  label: const Text('Delete'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: isUploading
                                      ? null
                                      : () => _sendDraft(draft),
                                  icon: isUploading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.cloud_upload_rounded),
                                  label: Text(
                                    isUploading ? 'Sending...' : 'Send now',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: SkeletonLoader(itemCount: 2),
        ),
        error: (error, _) =>
            Center(child: Text('Saved photos failed to load: $error')),
      ),
    );
  }

  String _timeLabel(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    }
    return '${difference.inDays}d ago';
  }
}

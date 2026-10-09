import 'dart:typed_data';

import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:flutter/material.dart';

/// The "Before Photos" section of the Job Details page.
///
/// Purely presentational: it shows the job's before photos as a grid, each
/// tile carrying its sync badge (pending / synced / failed), offers
/// **Add Before Photo** while [canAdd] is true (the job is `in_progress`),
/// and a Retry action while any upload sits in the queue's failed state.
/// All photo business logic lives in the cubit/repository — this widget only
/// reports taps.
class BeforePhotosSection extends StatelessWidget {
  const BeforePhotosSection({
    super.key,
    required this.photos,
    required this.failedIds,
    required this.canAdd,
    required this.isAdding,
    required this.onAdd,
    required this.onRetry,
    required this.loadBytes,
  });

  /// The job's before photos, ordered by capture time.
  final List<JobFile> photos;

  /// Ids of photos whose upload is currently `failed` in the sync queue.
  final Set<String> failedIds;

  /// Whether new before photos may be captured (job is `in_progress`).
  final bool canAdd;

  /// A photo is currently being registered locally — disables the button.
  final bool isAdding;

  /// Called when the user taps **Add Before Photo** (never while [isAdding]).
  final VoidCallback onAdd;

  /// Called when the user taps **Retry** while uploads have failed.
  final VoidCallback onRetry;

  /// Resolves the displayable bytes for a tile (lazy loading).
  final Future<Uint8List?> Function(JobFile file) loadBytes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool hasFailures = photos.any(
      (JobFile photo) => failedIds.contains(photo.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              l10n.beforePhotosTitle,
              style: context.textStyles.titleMedium,
            ),
            if (canAdd)
              FilledButton.icon(
                key: const Key('add_before_photo_button'),
                // The theme's buttons are full-width (infinite minimumSize);
                // inside this header row the button must size to its content.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: isAdding ? null : onAdd,
                icon: isAdding
                    ? const SizedBox(
                        width: AppDimensions.iconSm,
                        height: AppDimensions.iconSm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.photo_camera_rounded,
                        size: AppDimensions.iconMd,
                      ),
                label: Text(
                  isAdding ? l10n.uploadingLabel : l10n.addBeforePhotoButton,
                ),
              ),
          ],
        ),
        if (hasFailures) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, size: AppDimensions.iconMd),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(l10n.uploadFailedLabel)),
              TextButton(
                key: const Key('retry_before_photos_button'),
                onPressed: onRetry,
                child: Text(l10n.retryButton),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (photos.isEmpty)
          Text(l10n.noBeforePhotosYet, style: context.textStyles.bodyMedium)
        else
          GridView.count(
            key: const Key('before_photos_grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Two columns → clearly larger thumbnails; the tap preview on
            // each tile keeps full detail one gesture away.
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1,
            children: <Widget>[
              for (final JobFile photo in photos)
                BeforePhotoTile(
                  key: Key('before_photo_tile_${photo.id}'),
                  file: photo,
                  isFailed: failedIds.contains(photo.id),
                  loadBytes: loadBytes,
                ),
            ],
          ),
      ],
    );
  }
}

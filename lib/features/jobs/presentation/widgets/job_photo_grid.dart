import 'dart:typed_data';

import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:flutter/material.dart';

/// The photo grid shared by the **Before Photos** and **After Photos** steps.
///
/// The two steps differ only in their copy, their keys and which tile key
/// prefix they own — the layout, the sync badges and the preview behaviour are
/// identical, so they live here once. [BeforePhotoTile] is the app's existing
/// job-file tile (photos and signatures alike); this widget only decides how
/// many of them fit in a row.
class JobPhotoGrid extends StatelessWidget {
  const JobPhotoGrid({
    super.key,
    required this.gridKey,
    required this.tileKeyPrefix,
    required this.photos,
    required this.failedIds,
    required this.loadBytes,
  });

  /// Key of the grid itself (`before_photos_grid` / `after_photos_grid`).
  final Key gridKey;

  /// Prefix of the per-tile keys (`before` / `after`).
  final String tileKeyPrefix;

  /// The photos, ordered by capture time.
  final List<JobFile> photos;

  /// Ids of photos whose upload is currently `failed` in the sync queue.
  final Set<String> failedIds;

  /// Resolves the displayable bytes for a tile (lazy loading).
  final Future<Uint8List?> Function(JobFile file) loadBytes;

  /// Two large thumbnails on a phone; the wider the layout, the more of the
  /// width the grid uses instead of stretching two tiles across a browser
  /// window.
  static int columnsFor(double width) {
    if (width >= 840) {
      return 4;
    }
    if (width >= 560) {
      return 3;
    }
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          GridView.count(
            key: gridKey,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: columnsFor(constraints.maxWidth),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1,
            children: <Widget>[
              for (final JobFile photo in photos)
                BeforePhotoTile(
                  key: Key('${tileKeyPrefix}_photo_tile_${photo.id}'),
                  file: photo,
                  isFailed: failedIds.contains(photo.id),
                  loadBytes: loadBytes,
                ),
            ],
          ),
    );
  }
}

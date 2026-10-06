import 'dart:typed_data';

import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:flutter/material.dart';

/// One before photo in the grid.
///
/// Bytes are loaded lazily (local app storage first, Supabase Storage for
/// backend-only photos) so a job with many photos never loads every
/// full-resolution image up front.
///
/// The small badge mirrors the sync architecture's states — nothing is
/// invented on top:
/// * `failed` (queued upload in the queue's failed state) → error icon,
/// * `synced` (upload confirmed) → check icon,
/// * otherwise `pending` (queued / awaiting retry) → cloud-upload icon.
class BeforePhotoTile extends StatelessWidget {
  const BeforePhotoTile({
    super.key,
    required this.file,
    required this.isFailed,
    required this.loadBytes,
  });

  /// The photo to display.
  final JobFile file;

  /// The photo's queued upload is currently in the `failed` sync state.
  final bool isFailed;

  /// Resolves the displayable bytes (usually the repository via a use case).
  final Future<Uint8List?> Function(JobFile file) loadBytes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    final Widget badge = _badge(l10n);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: FutureBuilder<Uint8List?>(
        future: loadBytes(file),
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          final Uint8List? bytes = snapshot.data;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (bytes != null)
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              else
                Container(
                  color: AppColors.surfaceLight,
                  alignment: Alignment.center,
                  child: Icon(
                    snapshot.connectionState == ConnectionState.waiting
                        ? Icons.hourglass_empty_rounded
                        : Icons.photo_rounded,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              Positioned(
                right: 4,
                bottom: 4,
                child: badge,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _badge(AppLocalizations l10n) {
    final IconData icon;
    final Color color;
    final String tooltip;

    if (isFailed) {
      icon = Icons.error_rounded;
      color = AppColors.error;
      tooltip = l10n.uploadFailedLabel;
    } else if (file.syncState == JobFileSyncState.synced) {
      icon = Icons.check_circle_rounded;
      color = AppColors.success;
      tooltip = l10n.photoSyncedLabel;
    } else {
      icon = Icons.cloud_upload_rounded;
      color = AppColors.warning;
      tooltip = l10n.pendingSyncLabel;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

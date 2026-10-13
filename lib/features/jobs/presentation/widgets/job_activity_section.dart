import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_section_heading.dart';
import 'package:flutter/material.dart';

/// The job's own history, in the order it happened.
///
/// Every line is a fact that already exists in the loaded state — nothing is
/// inferred and nothing is invented:
///
/// * `jobs.assigned_at` / `started_at` / `completed_at` for the three lifecycle
///   events;
/// * each captured file's `captured_at` (the ORIGINAL capture time, preserved
///   through the whole sync path) for the photo and signature events;
/// * each captured file's sync state (`synced` / still queued / failed in the
///   queue) for the upload status beside it.
///
/// The timestamps are rendered with date AND time (`formatJobDateTime`) while
/// the record fields in [JobDetailsFields] show the date only, so the two
/// readings never look like duplicated rows: the fields are the record, this
/// list is when it happened.
///
/// The section renders nothing at all when there is no event to show — an empty
/// "activity" box on a job nobody has touched yet would be noise, not
/// information.
class JobActivitySection extends StatelessWidget {
  const JobActivitySection({
    super.key,
    required this.job,
    required this.beforePhotos,
    required this.afterPhotos,
    required this.signatureFiles,
    required this.failedIds,
  });

  final Job job;

  /// Files of each kind, ordered by capture time (as the cubit emits them).
  final List<JobFile> beforePhotos;
  final List<JobFile> afterPhotos;
  final List<JobFile> signatureFiles;

  /// Ids whose upload sits in the sync queue's `failed` state.
  final Set<String> failedIds;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<_ActivityEntry> entries = <_ActivityEntry>[];

    void addDate(DateTime? at, IconData icon, String label) {
      if (at == null) return;
      entries.add(_ActivityEntry(icon: icon, label: label, at: at));
    }

    void addFile(List<JobFile> files, IconData icon, String label) {
      final JobFile? latest = _latest(files);
      if (latest == null) return;
      final bool isFailed = failedIds.contains(latest.id);
      entries.add(
        _ActivityEntry(
          icon: icon,
          label: label,
          at: latest.capturedAt,
          syncLabel: _syncLabel(l10n, latest, isFailed),
          syncColor: _syncColor(latest, isFailed),
        ),
      );
    }

    // Chronological, like the workflow it records: assignment first, the
    // finished work last.
    addDate(job.assignedAt, Icons.assignment_turned_in_outlined, l10n.activityAssigned);
    addDate(job.startedAt, Icons.play_circle_outline_rounded, l10n.activityStarted);
    addFile(beforePhotos, Icons.photo_camera_outlined, l10n.activityBeforePhoto);
    addFile(afterPhotos, Icons.photo_camera_back_outlined, l10n.activityAfterPhoto);
    addFile(signatureFiles, Icons.draw_outlined, l10n.activitySignature);
    addDate(job.completedAt, Icons.check_circle_outline_rounded, l10n.activityCompleted);

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            JobSectionHeading(
              icon: Icons.history_rounded,
              title: l10n.jobActivityTitle,
            ),
            const SizedBox(height: AppSpacing.lg),
            for (int i = 0; i < entries.length; i++)
              _ActivityRow(
                entry: entries[i],
                isLast: i == entries.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  /// The most recently captured file of one kind — the line the technician
  /// last added, which is the one an upload state is meaningful for.
  static JobFile? _latest(List<JobFile> files) {
    if (files.isEmpty) return null;
    return files.reduce(
      (JobFile a, JobFile b) => a.capturedAt.isAfter(b.capturedAt) ? a : b,
    );
  }

  /// The sync state of a captured file, in the same vocabulary the photo tiles
  /// already use. A file whose upload the queue reports as failed reads
  /// "Sync failed" — a different string from the section's own "Upload failed"
  /// notice, so the two never read as a duplicate of each other. A file the
  /// server has confirmed reads "Synced"; anything else is still queued or in
  /// flight, i.e. "Pending sync".
  static String _syncLabel(
    AppLocalizations l10n,
    JobFile file,
    bool isFailed,
  ) {
    if (isFailed) {
      return l10n.syncFailedLabel;
    }
    return file.syncState == JobFileSyncState.synced
        ? l10n.syncedLabel
        : l10n.pendingSyncLabel;
  }

  static Color _syncColor(JobFile file, bool isFailed) {
    if (isFailed) {
      return AppColors.error;
    }
    return file.syncState == JobFileSyncState.synced
        ? AppColors.success
        : AppColors.warning;
  }
}

/// One line of [JobActivitySection]: icon, what happened, when, and — for
/// captured files — the upload state.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.isLast});

  final _ActivityEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final Color muted = context.colors.onSurfaceVariant;
    final String? syncLabel = entry.syncLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Icon(entry.icon, size: AppDimensions.iconSm, color: muted),
            ),
            if (!isLast)
              Container(
                width: 1,
                height: AppSpacing.xl,
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                color: context.colors.outlineVariant,
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: isLast ? 0 : AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.label, style: context.textStyles.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      formatJobDateTime(entry.at, context),
                      style: context.textStyles.bodySmall?.copyWith(
                        color: muted,
                      ),
                    ),
                    if (syncLabel != null)
                      Text(
                        '· $syncLabel',
                        style: context.textStyles.bodySmall?.copyWith(
                          color: entry.syncColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One resolved line of the activity log.
class _ActivityEntry {
  const _ActivityEntry({
    required this.icon,
    required this.label,
    required this.at,
    this.syncLabel,
    this.syncColor,
  });

  final IconData icon;
  final String label;
  final DateTime at;
  final String? syncLabel;
  final Color? syncColor;
}

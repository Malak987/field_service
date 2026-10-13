import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_status_badge.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// The job identity at the top of Job Details.
///
/// The frame brings together the facts a worker needs before acting: job
/// number, category, current server-backed status, customer, assignment and
/// the evidence sync state. The underlying data and permissions are unchanged;
/// this widget only makes their hierarchy explicit.
class JobDetailsHeader extends StatelessWidget {
  const JobDetailsHeader({
    super.key,
    required this.job,
    required this.mapper,
    required this.state,
  });

  final Job job;
  final JobLabelMapper mapper;
  final JobsState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String? customerName =
        state.selectedJobCustomer?.name ?? job.customerName;
    final bool isKitchen = job.jobType == JobCategory.kitchenRenovation;
    final String? technician = job.assignedEmployeeName?.trim().isEmpty ?? true
        ? null
        : job.assignedEmployeeName!.trim();
    final _EvidenceSyncState evidenceSync = _evidenceSyncState();

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  image: true,
                  label: l10n.appName,
                  child: ExcludeSemantics(
                    child: Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: const BoxDecoration(
                        color: AppColors.goldSurface,
                        borderRadius: AppRadius.logoBadge,
                      ),
                      child: Image.asset(
                        AuthLogo.assetName,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '#${job.jobNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: <Widget>[
                          Icon(
                            isKitchen
                                ? Icons.kitchen_outlined
                                : Icons.house_siding_outlined,
                            size: AppDimensions.iconSm,
                            color: context.colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              mapper.jobTypeLabel(job.jobType),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
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
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                JobStatusBadge(
                  label: mapper.statusLabel(job.status),
                  status: job.status,
                ),
                if (evidenceSync != _EvidenceSyncState.none)
                  AppStatusBadge(
                    icon: _syncIcon(evidenceSync),
                    label: _syncLabel(l10n, evidenceSync),
                    tone: _syncTone(evidenceSync),
                  ),
              ],
            ),
            if (customerName != null && customerName.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadius.banner,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.person_outline_rounded,
                      size: AppDimensions.iconMd,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        customerName.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                if (technician != null)
                  _HeaderMeta(
                    icon: Icons.engineering_outlined,
                    label: technician,
                  ),
                _HeaderMeta(
                  icon: Icons.event_outlined,
                  label: formatJobDate(job.assignedAt ?? job.createdAt, context),
                ),
                if (job.startedAt != null)
                  _HeaderMeta(
                    icon: Icons.play_circle_outline_rounded,
                    label: formatJobDateTime(job.startedAt!, context),
                  ),
              ],
            ),
            if (job.status.value == JobStatus.completed &&
                job.completedAt != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.successSurface,
                  borderRadius: AppRadius.banner,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.check_circle_rounded,
                      size: AppDimensions.iconMd,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.jobCompletedAt(
                          formatJobDateTime(job.completedAt!, context),
                        ),
                        style: context.textStyles.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _EvidenceSyncState _evidenceSyncState() {
    final List<JobFile> files = <JobFile>[
      ...state.beforePhotos,
      ...state.afterPhotos,
      ...state.signatureFiles,
    ];
    if (files.isEmpty) {
      return _EvidenceSyncState.none;
    }
    final Set<String> failedIds = <String>{
      ...state.beforePhotoFailedIds,
      ...state.afterPhotoFailedIds,
      ...state.signatureFailedIds,
    };
    if (files.any((JobFile file) => failedIds.contains(file.id))) {
      return _EvidenceSyncState.failed;
    }
    if (files.any(
      (JobFile file) => file.syncState != JobFileSyncState.synced,
    )) {
      return _EvidenceSyncState.pending;
    }
    return _EvidenceSyncState.synced;
  }

  static IconData _syncIcon(_EvidenceSyncState state) => switch (state) {
    _EvidenceSyncState.pending => Icons.cloud_upload_outlined,
    _EvidenceSyncState.failed => Icons.cloud_off_outlined,
    _EvidenceSyncState.synced => Icons.cloud_done_outlined,
    _EvidenceSyncState.none => Icons.cloud_outlined,
  };

  static String _syncLabel(
    AppLocalizations l10n,
    _EvidenceSyncState state,
  ) => switch (state) {
    _EvidenceSyncState.pending => l10n.pendingSyncLabel,
    _EvidenceSyncState.failed => l10n.syncFailedLabel,
    _EvidenceSyncState.synced => l10n.syncedLabel,
    _EvidenceSyncState.none => '',
  };

  static AppStatusTone _syncTone(_EvidenceSyncState state) => switch (state) {
    _EvidenceSyncState.pending => AppStatusTone.warning,
    _EvidenceSyncState.failed => AppStatusTone.danger,
    _EvidenceSyncState.synced => AppStatusTone.success,
    _EvidenceSyncState.none => AppStatusTone.neutral,
  };
}

enum _EvidenceSyncState { none, pending, failed, synced }

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = context.colors.onSurfaceVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: AppDimensions.iconSm, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

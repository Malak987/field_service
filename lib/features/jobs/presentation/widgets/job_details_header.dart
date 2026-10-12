import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// The identity block at the top of the Job Details page: which job this is,
/// what kind of work it is, who it is for, and its status.
///
/// Deliberately not a card. It used to sit in a boxed panel with a 4px burgundy
/// edge, which read as a fifth competing surface on a page that already stacks
/// one bordered panel per workflow step. Open text on the canvas keeps the
/// hierarchy flat: this is the page's title, the panels below are its content.
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
    final bool isCompleted = job.status.value == JobStatus.completed;
    final bool isKitchen = job.jobType == JobCategory.kitchenRenovation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: AppRadius.md,
              ),
              alignment: Alignment.center,
              child: Icon(
                isKitchen
                    ? Icons.kitchen_outlined
                    : Icons.house_siding_outlined,
                size: AppDimensions.iconLg,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '#${job.jobNumber}',
                    style: context.textStyles.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    mapper.jobTypeLabel(job.jobType),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            JobStatusBadge(
              label: mapper.statusLabel(job.status),
              status: job.status,
            ),
          ],
        ),
        if (customerName != null && customerName.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Icon(
                Icons.person_outline_rounded,
                size: AppDimensions.iconSm,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
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
        ],
        if (isCompleted && job.completedAt != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: AppRadius.control,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.check_circle_rounded,
                  size: AppDimensions.iconMd,
                  color: AppColors.primary,
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
    );
  }
}

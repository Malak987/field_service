import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// Jobs-list-specific card. Leaves the dashboard's existing job card unchanged.
class JobsListCard extends StatelessWidget {
  const JobsListCard({
    super.key,
    required this.job,
    required this.isAdmin,
    required this.onTap,
  });

  final Job job;
  final bool isAdmin;
  final VoidCallback onTap;

  String? _nextAction(AppLocalizations l10n) => switch (job.status.value) {
    JobStatus.assigned => l10n.startJobButton,
    JobStatus.started || JobStatus.inProgress => l10n.continueJobButton,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final (Color statusColor, _) = JobStatusBadge.styleFor(context, job.status);
    final String? nextAction = isAdmin ? null : _nextAction(l10n);
    final List<String> semanticParts = <String>[
      '${l10n.jobNumberLabel} ${job.jobNumber}',
      if (job.customerName?.trim().isNotEmpty ?? false) job.customerName!.trim(),
      mapper.jobTypeLabel(job.jobType),
      mapper.statusLabel(job.status),
      if (isAdmin && (job.assignedEmployeeName?.trim().isNotEmpty ?? false))
        '${l10n.assignedTechnicianLabel}: ${job.assignedEmployeeName!.trim()}',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        label: semanticParts.join(', '),
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 112),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: statusColor, width: 4),
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        '#${job.jobNumber}',
                        style: context.textStyles.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      JobStatusBadge(
                        label: mapper.statusLabel(job.status),
                        status: job.status,
                      ),
                    ],
                  ),
                  if (job.customerName?.trim().isNotEmpty ?? false) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      job.customerName!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Icon(
                        job.jobType == JobCategory.kitchenRenovation
                            ? Icons.kitchen_outlined
                            : Icons.house_siding_outlined,
                        size: AppDimensions.iconMd,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          mapper.jobTypeLabel(job.jobType),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isAdmin &&
                      (job.assignedEmployeeName?.trim().isNotEmpty ?? false))
                    _DetailLine(
                      icon: Icons.person_outline_rounded,
                      text:
                          '${l10n.assignedTechnicianLabel}: ${job.assignedEmployeeName!.trim()}',
                    ),
                  if (job.assignedAt != null)
                    _DetailLine(
                      icon: Icons.calendar_today_outlined,
                      text:
                          '${l10n.assignedDateLabel}: ${formatJobDate(job.assignedAt!, context)}',
                    ),
                  if (job.description?.trim().isNotEmpty ?? false) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      job.description!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (nextAction != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: AppDimensions.iconMd,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            l10n.nextActionLabel(nextAction),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: AppDimensions.iconLg,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Row(
      children: <Widget>[
        Icon(icon, size: AppDimensions.iconSm, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

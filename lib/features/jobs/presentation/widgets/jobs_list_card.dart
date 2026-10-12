import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// One row of the jobs list.
///
/// Built for scanning, not for decoration: the job number and the status are
/// the first things the eye lands on, the customer is the second, and
/// everything else is metadata on a single quiet line. There is no card, no
/// elevation and no chevron — the whole row is the tap target and the list
/// around it supplies the hairlines.
///
/// Status still travels twice (badge text *and* colour) so it never depends on
/// colour alone.
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
    final String? nextAction = isAdmin ? null : _nextAction(l10n);
    final String customerName = job.customerName?.trim() ?? '';
    final String technicianName = job.assignedEmployeeName?.trim() ?? '';
    final String description = job.description?.trim() ?? '';

    // Field names live in the semantics tree; on screen the icon carries them.
    // Repeating "Assigned Technician:" on every row of a long list is noise.
    final List<String> semanticParts = <String>[
      '${l10n.jobNumberLabel} ${job.jobNumber}',
      if (customerName.isNotEmpty) customerName,
      mapper.jobTypeLabel(job.jobType),
      mapper.statusLabel(job.status),
      if (isAdmin && technicianName.isNotEmpty)
        '${l10n.assignedTechnicianLabel}: $technicianName',
      if (job.assignedAt != null)
        '${l10n.assignedDateLabel}: ${formatJobDate(job.assignedAt!, context)}',
      if (nextAction != null) l10n.nextActionLabel(nextAction),
    ];

    return Semantics(
      container: true,
      button: true,
      label: semanticParts.join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '#${job.jobNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    JobStatusBadge(
                      label: mapper.statusLabel(job.status),
                      status: job.status,
                    ),
                  ],
                ),
                if (customerName.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    customerName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyLarge,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _Meta(
                      icon: job.jobType == JobCategory.kitchenRenovation
                          ? Icons.kitchen_outlined
                          : Icons.house_siding_outlined,
                      text: mapper.jobTypeLabel(job.jobType),
                    ),
                    if (isAdmin && technicianName.isNotEmpty)
                      _Meta(
                        icon: Icons.person_outline_rounded,
                        text: technicianName,
                      ),
                    if (job.assignedAt != null)
                      _Meta(
                        icon: Icons.event_outlined,
                        text: formatJobDate(job.assignedAt!, context),
                      ),
                  ],
                ),
                if (description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (nextAction != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: AppDimensions.iconSm,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          l10n.nextActionLabel(nextAction),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small icon + text pair on the metadata line.
class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color color = context.colors.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: AppDimensions.iconSm, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

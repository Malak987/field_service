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

/// The job row of the app — used by the jobs list and by both dashboards.
///
/// Built for scanning, not for decoration: the job number and the status are
/// what the eye lands on, the customer is second, and everything else is
/// metadata on a quiet icon line. It draws no card of its own; it lives inside
/// an [AppSurfacePanel], which supplies the white surface, the hairline and the
/// [Material] the [InkWell] paints its splash on.
///
/// The design is intentionally the ONLY job row in the app: the same widget
/// serves the jobs list, the technician's queue and any future list, so a job
/// can never look like two different things depending on where it is shown.
///
/// * An administrator additionally sees who the job is assigned to.
/// * A technician sees the next action the job is waiting for — derived purely
///   from the existing status, no new state and no rule moved into the UI.
/// * Status travels twice (badge text *and* colour) so it never depends on
///   colour alone.
class JobsListItem extends StatelessWidget {
  const JobsListItem({
    super.key,
    required this.job,
    required this.showAssignedTechnician,
    required this.onTap,
    this.showNextAction = false,
  });

  final Job job;

  /// Admins also see who the job is assigned to; technicians do not.
  final bool showAssignedTechnician;

  /// Technicians additionally see the next action the job waits for.
  final bool showNextAction;

  /// Called when the row is tapped (e.g. navigate to the details route).
  final VoidCallback onTap;

  /// The next action a technician can take, derived ONLY from the existing
  /// job status — no new state, no business rule moved into the UI.
  String? _nextAction(AppLocalizations l10n) {
    if (!showNextAction) {
      return null;
    }
    return switch (job.status.value) {
      JobStatus.assigned => l10n.startJobButton,
      JobStatus.started || JobStatus.inProgress => l10n.continueJobButton,
      // Completed/cancelled jobs are read-only history: no next action.
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final String? nextAction = _nextAction(l10n);
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
      if (showAssignedTechnician && technicianName.isNotEmpty)
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
                    if (showAssignedTechnician && technicianName.isNotEmpty)
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

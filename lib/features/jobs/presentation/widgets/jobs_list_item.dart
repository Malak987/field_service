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
/// * An administrator additionally sees who the job is assigned to — while the
///   job is still open. A closed job (completed / cancelled) shows the date it
///   was closed instead: "who holds this" is live information an administrator
///   acts on, whereas the assignee of finished work is history, and the row has
///   no room to repeat both. The assignee itself stays visible on the job.
/// * A technician sees the next action the job is waiting for — derived purely
///   from the existing status, no new state and no rule moved into the UI.
/// * Status travels twice (badge text *and* colour) so it never depends on
///   colour alone.
///
/// [showCategory] is for the lists that already NAME the categories themselves
/// — the jobs list puts its category filter chips directly above the rows, so
/// printing "Kitchen Renovation" again on every row would both duplicate the
/// vocabulary and drown the facts that differ per job. Such a list passes
/// `false`: the row keeps the category's glyph (and its accessible name) and
/// leaves the words to the chips. A dashboard, which has no chips, keeps the
/// default `true`.
class JobsListItem extends StatelessWidget {
  const JobsListItem({
    super.key,
    required this.job,
    required this.showAssignedTechnician,
    required this.onTap,
    this.showNextAction = false,
    this.showCategory = true,
  });

  final Job job;

  /// Admins also see who the job is assigned to; technicians do not.
  final bool showAssignedTechnician;

  /// Technicians additionally see the next action the job waits for.
  final bool showNextAction;

  /// Whether the category is spelled out on the metadata line. `false` on a
  /// list that already names the categories in its filter chips (see the class
  /// doc): the glyph and the accessible name stay either way.
  final bool showCategory;

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
    final String status = job.status.value;
    // Closed work: the assignee gives way to the date it was closed (see the
    // class doc). Everything else keeps the live assignment line.
    final bool isClosed =
        status == JobStatus.completed || status == JobStatus.cancelled;
    final bool showTechnician =
        showAssignedTechnician && technicianName.isNotEmpty && !isClosed;

    // Field names live in the semantics tree; on screen the icon carries them.
    // Repeating "Assigned Technician:" on every row of a long list is noise.
    final List<String> semanticParts = <String>[
      '${l10n.jobNumberLabel} ${job.jobNumber}',
      if (customerName.isNotEmpty) customerName,
      mapper.jobTypeLabel(job.jobType),
      mapper.statusLabel(job.status),
      if (showTechnician)
        '${l10n.assignedTechnicianLabel}: $technicianName',
      if (job.assignedAt != null)
        '${l10n.assignedDateLabel}: ${formatJobDate(job.assignedAt!, context)}',
      if (isClosed && job.completedAt != null)
        '${l10n.completedDateLabel}: '
            '${formatJobDate(job.completedAt!, context)}',
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
                    if (showCategory)
                      _Meta(
                        icon: job.jobType == JobCategory.kitchenRenovation
                            ? Icons.kitchen_outlined
                            : Icons.house_siding_outlined,
                        text: mapper.jobTypeLabel(job.jobType),
                      )
                    else
                      // Glyph only: the words live in the list's chips, but the
                      // name stays reachable on hover/long-press and the
                      // semantics below still read it out.
                      Tooltip(
                        message: mapper.jobTypeLabel(job.jobType),
                        child: Icon(
                          job.jobType == JobCategory.kitchenRenovation
                              ? Icons.kitchen_outlined
                              : Icons.house_siding_outlined,
                          size: AppDimensions.iconSm,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    if (showTechnician)
                      _Meta(
                        icon: Icons.person_outline_rounded,
                        text: technicianName,
                      ),
                    if (job.assignedAt != null)
                      _Meta(
                        icon: Icons.event_outlined,
                        text: formatJobDate(job.assignedAt!, context),
                      ),
                    if (isClosed && job.completedAt != null)
                      _Meta(
                        icon: Icons.check_circle_outline_rounded,
                        text: formatJobDate(job.completedAt!, context),
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

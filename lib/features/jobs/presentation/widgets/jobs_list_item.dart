import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// One card in the jobs list (also reused inline on the technician home).
///
/// Purely presentational: all labels come through localization and the
/// navigation target is injected via [onTap] (no GoRouter / Navigator usage
/// inside this widget).
///
/// Visual language: a status-coloured accent bar (the SAME colours as
/// [JobStatusBadge]) makes the state scannable at a glance without adding
/// clutter; for technicians the card additionally shows the next action the
/// job is waiting for — derived purely from the existing status.
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

  /// Called when the card is tapped (e.g. navigate to the details route).
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
    final (Color statusColor, _) = JobStatusBadge.styleFor(context, job.status);
    final String? nextAction = _nextAction(l10n);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Status accent bar — same semantic colour as the badge.
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: AppRadius.circular,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            '#${job.jobNumber}',
                            style: context.textStyles.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          JobStatusBadge(
                            label: mapper.statusLabel(job.status),
                            status: job.status,
                          ),
                        ],
                      ),
                      if (job.customerName != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          job.customerName!,
                          style: context.textStyles.titleSmall,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        mapper.jobTypeLabel(job.jobType),
                        style: context.textStyles.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      if (job.assignedAt != null)
                        Text(
                          '${l10n.assignedDateLabel}: '
                          '${formatJobDate(job.assignedAt!, context)}',
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      if (showAssignedTechnician &&
                          job.assignedEmployeeName != null)
                        Text(
                          '${l10n.assignedTechnicianLabel}: '
                          '${job.assignedEmployeeName}',
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      if (nextAction != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.trending_flat_rounded,
                              size: 18,
                              color: context.colors.primary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                l10n.nextActionLabel(nextAction),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textStyles.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

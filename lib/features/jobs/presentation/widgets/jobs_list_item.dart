import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// One card in the jobs list.
///
/// Purely presentational: all labels come through localization and the
/// navigation target is injected via [onTap] (no GoRouter / Navigator usage
/// inside this widget).
class JobsListItem extends StatelessWidget {
  const JobsListItem({
    super.key,
    required this.job,
    required this.showAssignedTechnician,
    required this.onTap,
  });

  final Job job;

  /// Admins also see who the job is assigned to; technicians do not.
  final bool showAssignedTechnician;

  /// Called when the card is tapped (e.g. navigate to the details route).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
                Text(job.customerName!, style: context.textStyles.titleSmall),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                mapper.jobTypeLabel(job.jobType),
                style: context.textStyles.bodySmall,
              ),
              if (job.assignedAt != null)
                Text(
                  '${l10n.assignedDateLabel}: '
                  '${formatJobDate(job.assignedAt!, context)}',
                  style: context.textStyles.bodySmall,
                ),
              if (showAssignedTechnician &&
                  job.assignedEmployeeName != null)
                Text(
                  '${l10n.assignedTechnicianLabel}: '
                  '${job.assignedEmployeeName}',
                  style: context.textStyles.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

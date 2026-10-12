import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:flutter/material.dart';

/// Compact progress meter derived exclusively from this job's existing
/// workflow facts. It does not enable, disable, or change any workflow action.
class WorkflowProgress extends StatelessWidget {
  const WorkflowProgress({
    super.key,
    required this.completed,
    required this.total,
    required this.label,
    required this.title,
  });

  final int completed;
  final int total;
  final String label;
  final String title;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.textStyles.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            container: true,
            label: '$title: $label',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: AppRadius.circular,
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: total == 0 ? 0 : completed / total,
                  backgroundColor: context.colors.outlineVariant,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The workflow-state line shown in place of the Start Job button once the job
/// is `in_progress`: "Started: `<server date>`". Purely presentational — the
/// value comes from `jobs.started_at` (database-generated), formatted with
/// `formatJobDate`, i.e. with the SAME convention as the "Start Date" field of
/// the Job Information card. (The activity log keeps date AND time, because
/// there the timeline — not the date — is the point.)
class StartedAtLine extends StatelessWidget {
  const StartedAtLine({super.key, required this.startedAt});

  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Row(
      children: <Widget>[
        const Icon(Icons.access_time_rounded, size: AppDimensions.iconMd),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            l10n.jobStartedAt(formatJobDate(startedAt, context)),
            style: context.textStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}

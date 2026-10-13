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
  Widget build(BuildContext context) {
    final int safeTotal = total < 1 ? 1 : total;
    final int safeCompleted = completed.clamp(0, safeTotal).toInt();

    return Material(
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: AppDimensions.buttonHeightCompact,
                  height: AppDimensions.buttonHeightCompact,
                  decoration: const BoxDecoration(
                    color: AppColors.goldSurface,
                    borderRadius: AppRadius.banner,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.account_tree_outlined,
                    size: AppDimensions.iconMd,
                    color: AppColors.goldDeep,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: context.textStyles.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        label,
                        style: context.textStyles.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              container: true,
              label: '$title: $label',
              child: ExcludeSemantics(
                child: Row(
                  children: <Widget>[
                    for (int index = 0; index < safeTotal; index++) ...<Widget>[
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: index < safeCompleted
                                ? AppColors.success
                                : context.colors.outlineVariant,
                            borderRadius: AppRadius.circular,
                          ),
                        ),
                      ),
                      if (index < safeTotal - 1)
                        const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

    return Container(
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
            Icons.check_circle_outline_rounded,
            size: AppDimensions.iconMd,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.jobStartedAt(formatJobDate(startedAt, context)),
              style: context.textStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';

/// The Jobs List's responsive job card.
///
/// This component belongs to the list rather than the shared dashboard row:
/// the list has space for a clear Details affordance and a timestamp, while
/// dashboard rows stay deliberately compact. It still reuses the shared status
/// badge, label mapping and theme tokens so a job's language never drifts.
class JobsListCard extends StatelessWidget {
  const JobsListCard({
    super.key,
    required this.job,
    required this.isAdmin,
    required this.onTap,
  });

  final Job job;

  /// Technicians only see their own data; admins may additionally see the
  /// assigned technician name that the existing query has already returned.
  final bool isAdmin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final Color accent = JobStatusBadge.styleFor(context, job.status).$1;
    final String customerName = job.customerName?.trim() ?? '';
    final String technicianName = job.assignedEmployeeName?.trim() ?? '';
    final String description = job.description?.trim() ?? '';
    final String? nextAction = _nextAction(l10n);
    final DateTime timestamp =
        job.completedAt ?? job.startedAt ?? job.assignedAt ?? job.updatedAt;
    final List<String> semantics = <String>[
      '${l10n.jobNumberLabel} ${job.jobNumber}',
      if (customerName.isNotEmpty) customerName,
      mapper.jobTypeLabel(job.jobType),
      mapper.statusLabel(job.status),
      if (isAdmin && technicianName.isNotEmpty)
        '${l10n.assignedTechnicianLabel}: $technicianName',
      formatJobDateTime(timestamp, context),
      if (nextAction != null) l10n.nextActionLabel(nextAction),
      l10n.jobDetailsTitle,
    ];

    return Semantics(
      container: true,
      button: true,
      label: semantics.join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: context.colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(width: 4, color: accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
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
                                  style: context.textStyles.titleLarge,
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
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              customerName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.titleMedium,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.sm,
                            children: <Widget>[
                              _JobCardMeta(
                                icon:
                                    job.jobType ==
                                        JobCategory.kitchenRenovation
                                    ? Icons.kitchen_outlined
                                    : Icons.house_siding_outlined,
                                text: mapper.jobTypeLabel(job.jobType),
                              ),
                              _JobCardMeta(
                                icon: Icons.schedule_outlined,
                                text: formatJobDateTime(timestamp, context),
                              ),
                              if (isAdmin && technicianName.isNotEmpty)
                                _JobCardMeta(
                                  icon: Icons.person_outline_rounded,
                                  text: technicianName,
                                ),
                            ],
                          ),
                          if (description.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (nextAction != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: AppDimensions.iconSm,
                                  color: context.colors.primary,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
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
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              onPressed: onTap,
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: AppDimensions.iconSm,
                              ),
                              label: Text(l10n.jobDetailsTitle),
                            ),
                          ),
                        ],
                      ),
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

  String? _nextAction(AppLocalizations l10n) => switch (job.status.value) {
    JobStatus.assigned => l10n.startJobButton,
    JobStatus.started || JobStatus.inProgress => l10n.continueJobButton,
    _ => null,
  };
}

class _JobCardMeta extends StatelessWidget {
  const _JobCardMeta({required this.icon, required this.text});

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

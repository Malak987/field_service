import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_detail_field.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_empty_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Read-only job details (route `/jobs/:id`).
///
/// No editing, photos, signature or completion workflow yet — the page only
/// presents the data that exists in `public.jobs` (plus the joined customer /
/// technician names).
class JobDetailsPage extends StatelessWidget {
  const JobDetailsPage({super.key, required this.jobId});

  /// The `:id` path parameter of the `/jobs/:id` route.
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobById(jobId),
      child: _JobDetailsView(jobId: jobId),
    );
  }
}

class _JobDetailsView extends StatelessWidget {
  const _JobDetailsView({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.jobDetailsTitle)),
      body: BlocBuilder<JobsCubit, JobsState>(
        builder: (BuildContext context, JobsState state) {
          final JobsCubit cubit = context.read<JobsCubit>();

          switch (state.status) {
            case JobsStatus.initial:
            case JobsStatus.loading:
              return const JobsLoadingView();

            case JobsStatus.failure:
              return JobsErrorState(
                onRetry: () => cubit.loadJobById(jobId),
              );

            case JobsStatus.success:
              final Job? job = state.selectedJob;
              if (job == null) {
                return const JobsEmptyState();
              }

              return ListView(
                padding: AppSpacing.pagePadding,
                children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '#${job.jobNumber}',
                            style: context.textStyles.titleLarge,
                          ),
                          const Spacer(),
                          JobStatusBadge(
                            label: mapper.statusLabel(job.status),
                            status: job.status,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: _buildFields(context, job, mapper),
                    ),
                  ),
                ],
              );
          }
        },
      ),
    );
  }

  /// Builds the ordered, role-independent detail fields. Fields whose value
  /// is not yet available (null in the database) are simply omitted.
  Widget _buildFields(
    BuildContext context,
    Job job,
    JobLabelMapper mapper,
  ) {
    final AppLocalizations l10n = context.l10n;

    final List<Widget> fields = <Widget>[];

    void add(String label, String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      if (fields.isNotEmpty) {
        fields.add(const SizedBox(height: AppSpacing.lg));
      }
      fields.add(JobDetailField(label: label, value: value));
    }

    add(l10n.customerLabel, job.customerName);
    add(l10n.assignedTechnicianLabel, job.assignedEmployeeName);
    add(l10n.jobTypeLabel, mapper.jobTypeLabel(job.jobType));
    add(l10n.statusLabel, mapper.statusLabel(job.status));
    add(l10n.assignedDateLabel, job.assignedAt == null ? null : formatJobDate(job.assignedAt!, context));
    add(l10n.startDateLabel, job.startedAt == null ? null : formatJobDate(job.startedAt!, context));
    add(l10n.completedDateLabel, job.completedAt == null ? null : formatJobDate(job.completedAt!, context));
    add(l10n.createdAtLabel, formatJobDate(job.createdAt, context));
    add(l10n.expiresAtLabel, formatJobDate(job.expiresAt, context));
    add(l10n.descriptionLabel, job.description);

    if (fields.isEmpty) {
      return const JobsEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }
}

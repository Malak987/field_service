import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_empty_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Jobs list for both roles.
///
/// The role is read from the authenticated [AppUser] (`AppUser.isAdmin`) —
/// there is no role selector in the UI. Which rows RLS returns for each role
/// is enforced by Supabase; this page only adapts the label and the extra
/// "assigned technician" line for admins.
class JobsPage extends StatelessWidget {
  const JobsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin =
        context.read<AuthenticationCubit?>()?.state.user?.isAdmin ?? false;

    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobs(),
      child: _JobsPageView(isAdmin: isAdmin),
    );
  }
}

class _JobsPageView extends StatelessWidget {
  const _JobsPageView({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? l10n.jobsTitle : l10n.myJobsTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          IconButton(
            tooltip: l10n.logoutButton,
            icon: const Icon(Icons.logout_outlined, size: AppDimensions.iconMd),
            onPressed: () {
              context.read<AuthenticationCubit?>()?.signOut();
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // Create & Assign Job is the admin's workflow — technicians execute
      // jobs, they never create them. The route is additionally guarded by
      // the router (deep links) and by the `create_job` RPC (server side).
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              key: const Key('create_job_fab'),
              onPressed: () async {
                await context.push(AppRoutes.jobCreate);
                if (context.mounted) {
                  // The new job exists by the time the form pops — refresh
                  // so it appears in the list without a manual pull.
                  context.read<JobsCubit>().loadJobs();
                }
              },
              icon: const Icon(Icons.add_rounded, size: AppDimensions.iconMd),
              label: Text(l10n.createJobButton),
            )
          : null,
      body: BlocBuilder<JobsCubit, JobsState>(
        builder: (BuildContext context, JobsState state) {
          final JobsCubit cubit = context.read<JobsCubit>();

          switch (state.status) {
            case JobsStatus.initial:
            case JobsStatus.loading:
              return const JobsLoadingView();

            case JobsStatus.failure:
              return JobsErrorState(onRetry: cubit.loadJobs);

            case JobsStatus.success:
              final List<Job> jobs = state.jobs;
              if (jobs.isEmpty) {
                return const JobsEmptyState();
              }

              return RefreshIndicator(
                onRefresh: cubit.loadJobs,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.pagePadding,
                  itemCount: jobs.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (BuildContext context, int index) {
                    final Job job = jobs[index];
                    return JobsListItem(
                      job: job,
                      showAssignedTechnician: isAdmin,
                      onTap: () {
                        context.goNamed(
                          'jobDetails',
                          pathParameters: <String, String>{'id': job.id},
                        );
                      },
                    );
                  },
                ),
              );
          }
        },
      ),
    );
  }
}

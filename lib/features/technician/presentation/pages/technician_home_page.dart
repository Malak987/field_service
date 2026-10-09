import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/home_navigation_tile.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/dashboard_category_card.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Technician home (route `/` for technician roles).
///
/// Built for field work: a personalised welcome, the CURRENT job front and
/// centre with a one-tap "Continue Job", the remaining assigned jobs below
/// it, and a proper empty state when nothing has been assigned yet.
/// Customer management stays admin-only — no tile, no route (the router
/// guard refuses `/customers` for technicians regardless of this screen).
class TechnicianHomePage extends StatelessWidget {
  const TechnicianHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.technicianHomeTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          IconButton(
            tooltip: l10n.logoutButton,
            icon: const Icon(Icons.logout_outlined, size: AppDimensions.iconMd),
            onPressed: isLoading
                ? null
                : () => context.read<AuthenticationCubit>().signOut(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(isAdmin: false, selectedIndex: 0),
      body: BlocProvider<JobsCubit>(
        create: (_) => sl<JobsCubit>()..loadJobs(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppSpacing.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _HeaderCard(user: user),
                const SizedBox(height: AppSpacing.xl),
                const _JobsSections(),
                const SizedBox(height: AppSpacing.xl),
                const _TechnicianOverviewAndCategories(),
                const SizedBox(height: AppSpacing.md),
                // The existing entry into the full My Jobs list — kept with
                // its stable key so behaviour (and tests) are unchanged.
                HomeNavigationTile(
                  key: const Key('nav_jobs'),
                  icon: Icons.event_note_outlined,
                  label: l10n.viewJobsButton,
                  onTap: () => context.go(AppRoutes.jobs),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Personalised welcome header (real name or e-mail — never invented).
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.user});

  final AppUser? user;

  String get _displayName {
    final String? name = user?.name;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return user?.email ?? '';
  }

  String get _initials {
    final List<String> parts = _displayName
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primarySurface,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: context.textStyles.titleLarge?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_displayName.isNotEmpty)
                    Text(
                      l10n.welcomeNameLabel(_displayName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    Text(
                      l10n.welcomeTechnician,
                      style: context.textStyles.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.roleTechnicianLabel,
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.construction_outlined,
              size: AppDimensions.iconXl,
              color: AppColors.goldAccent,
            ),
          ],
        ),
      ),
    );
  }
}

/// The job sections derived from the REAL loaded jobs:
/// * loading — a small centered spinner,
/// * failure — the shared retry-able error state,
/// * success — featured in-progress job (with Continue Job) plus the
///   remaining assigned jobs, or the professional empty state.
class _JobsSections extends StatelessWidget {
  const _JobsSections();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final JobsCubit cubit = context.read<JobsCubit>();

        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xxxl),
              child: Center(
                child: SizedBox(
                  width: AppDimensions.buttonSpinnerSize,
                  height: AppDimensions.buttonSpinnerSize,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            );
          case JobsStatus.failure:
            return JobsErrorState(onRetry: cubit.loadJobs);
          case JobsStatus.success:
            final List<Job> jobs = state.jobs;
            if (jobs.isEmpty) {
              return const _NoAssignedJobs();
            }

            final List<Job> inProgress = jobs
                .where((Job j) =>
                    j.status.value == JobStatus.inProgress ||
                    j.status.value == JobStatus.started)
                .toList();
            final List<Job> assigned = jobs
                .where((Job j) => j.status.value == JobStatus.assigned)
                .toList();
            final AppLocalizations l10n = context.l10n;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final Job job in inProgress) ...<Widget>[
                  _SectionLabel(label: l10n.currentJobTitle),
                  const SizedBox(height: AppSpacing.md),
                  _ContinueJobCard(job: job),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (assigned.isNotEmpty) ...<Widget>[
                  _SectionLabel(label: l10n.myJobsTitle),
                  const SizedBox(height: AppSpacing.md),
                  for (final Job job in assigned) ...<Widget>[
                    JobsListItem(
                      job: job,
                      showAssignedTechnician: false,
                      showNextAction: true,
                      onTap: () => _openJob(context, job.id),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            );
        }
      },
    );
  }

  void _openJob(BuildContext context, String jobId) {
    context.goNamed(
      'jobDetails',
      pathParameters: <String, String>{'id': jobId},
    );
  }
}

/// Summaries and category shortcuts based only on the jobs visible to this
/// authenticated technician (the Jobs query is scoped by the existing RLS).
class _TechnicianOverviewAndCategories extends StatelessWidget {
  const _TechnicianOverviewAndCategories();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final bool hasData = state.status == JobsStatus.success;
        final List<Job> jobs = hasData ? state.jobs : const <Job>[];
        final int assigned = jobs
            .where((Job job) => job.status.value == JobStatus.assigned)
            .length;
        final int inProgress = jobs
            .where((Job job) =>
                job.status.value == JobStatus.inProgress ||
                job.status.value == JobStatus.started)
            .length;
        final int completed = jobs
            .where((Job job) => job.status.value == JobStatus.completed)
            .length;
        final int kitchen = jobs
            .where((Job job) => job.jobType == JobCategory.kitchenRenovation)
            .length;
        final int home = jobs
            .where((Job job) => job.jobType == JobCategory.homeRenovation)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SectionLabel(label: l10n.overviewTitle),
            const SizedBox(height: AppSpacing.md),
            if (hasData)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double itemWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
                      return Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: <Widget>[
                          _TechnicianStat(label: l10n.totalJobsLabel, value: jobs.length, width: itemWidth),
                          _TechnicianStat(label: l10n.statusAssigned, value: assigned, width: itemWidth),
                          _TechnicianStat(label: l10n.statusInProgress, value: inProgress, width: itemWidth),
                          _TechnicianStat(label: l10n.statusCompleted, value: completed, width: itemWidth),
                        ],
                      );
                    },
                  ),
                ),
              )
            else if (state.status == JobsStatus.loading || state.status == JobsStatus.initial)
              const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel(label: l10n.categoriesTitle),
            const SizedBox(height: AppSpacing.md),
            DashboardCategoryCard(
              key: const Key('category_card_kitchen'),
              title: l10n.jobCategoryKitchenRenovation,
              icon: Icons.kitchen_outlined,
              jobCount: hasData ? kitchen : null,
              countLabel: l10n.jobsCountLabel,
              semanticLabel: '${l10n.jobCategoryKitchenRenovation}${hasData ? ', ${l10n.jobsCountLabel(kitchen)}' : ''}',
              isKitchen: true,
              onTap: () => context.go('${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}'),
            ),
            const SizedBox(height: AppSpacing.md),
            DashboardCategoryCard(
              key: const Key('category_card_home_renovation'),
              title: l10n.jobCategoryHomeRenovation,
              icon: Icons.house_siding_outlined,
              jobCount: hasData ? home : null,
              countLabel: l10n.jobsCountLabel,
              semanticLabel: '${l10n.jobCategoryHomeRenovation}${hasData ? ', ${l10n.jobsCountLabel(home)}' : ''}',
              isKitchen: false,
              onTap: () => context.go('${AppRoutes.jobs}?category=${JobCategory.homeRenovation}'),
            ),
          ],
        );
      },
    );
  }
}

class _TechnicianStat extends StatelessWidget {
  const _TechnicianStat({required this.label, required this.value, required this.width});

  final String label;
  final int value;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      label: '$label: $value',
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    ),
  );
}

/// Small uppercase section heading.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: context.textStyles.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.colors.onSurfaceVariant,
      ),
    );
  }
}

/// The featured card for an in-progress job: identity at a glance plus the
/// one-tap Continue Job action into the job details.
class _ContinueJobCard extends StatelessWidget {
  const _ContinueJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.goNamed(
          'jobDetails',
          pathParameters: <String, String>{'id': job.id},
        ),
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
                      style: context.textStyles.titleLarge,
                    ),
                  ),
                  JobStatusBadge(
                    label: mapper.statusLabel(job.status),
                    status: job.status,
                  ),
                ],
              ),
              if ((job.customerName ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(job.customerName!, style: context.textStyles.titleSmall),
              ],
              const SizedBox(height: AppSpacing.xxs),
              Text(
                mapper.jobTypeLabel(job.jobType),
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: Key('continue_job_${job.id}'),
                  onPressed: () => context.goNamed(
                    'jobDetails',
                    pathParameters: <String, String>{'id': job.id},
                  ),
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    size: AppDimensions.iconMd,
                  ),
                  label: Text(l10n.continueJobButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Professional empty state: icon + title + explanation, localized.
class _NoAssignedJobs extends StatelessWidget {
  const _NoAssignedJobs();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Card(
      key: const Key('tech_jobs_empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxxl,
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.goldSurface,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.event_note_outlined,
                size: 32,
                color: AppColors.goldDeep,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.noAssignedJobsTitle,
              textAlign: TextAlign.center,
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.noAssignedJobsSubtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

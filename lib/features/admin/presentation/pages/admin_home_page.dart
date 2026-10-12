import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/utils/date_formatter.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/app_dashboard_header.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_section_header.dart';
import 'package:field_service/core/widgets/app_state_views.dart';
import 'package:field_service/core/widgets/app_stat_tile.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/dashboard_category_card.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Admin dashboard (route `/` for admin roles).
///
/// Ordered by what an administrator actually does in a day, and deliberately
/// not as six interchangeable blocks — the screen has one loud thing (the
/// numbers), one primary action (create a job) and everything else recedes:
///
/// 1. header — who you are and what day it is;
/// 2. the overview — four real counts as tiles, comparable at a glance;
/// 3. the actions — create a job first, then the two places work is reviewed;
/// 4. administration — quiet list rows for the two management areas;
/// 5. categories;
/// 6. the most recently touched jobs, so "what moved since I last looked" is
///    one glance instead of a trip into the list and a scan for dates.
///
/// Every number comes from the shared [JobsCubit] (the same local mirror the
/// jobs list reads). On failure the overview shows an error with a retry — it
/// never renders a figure it does not have.
class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobs(),
      child: AppPageBody(
        appBar: AppBar(
          title: Text(l10n.adminDashboardTitle),
          actions: <Widget>[
            // Account & settings live next to sign-out rather than buried in a
            // tab: language, password and profile are all reached from there.
            IconButton(
              key: const Key('nav_account'),
              tooltip: l10n.accountSettingsTooltip,
              icon: const Icon(
                Icons.person_outline_rounded,
                size: AppDimensions.iconMd,
              ),
              onPressed: () => context.push(AppRoutes.account),
            ),
            IconButton(
              tooltip: l10n.logoutButton,
              icon: const Icon(
                Icons.logout_outlined,
                size: AppDimensions.iconMd,
              ),
              onPressed: isLoading
                  ? null
                  : () => context.read<AuthenticationCubit>().signOut(),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        bottomNavigationBar: const AppBottomNav(
          isAdmin: true,
          selectedIndex: 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppDashboardHeader(
              greeting: _greeting(context, user, l10n),
              subtitle: l10n.roleAdminLabel,
              dateLabel: formatFullDate(DateTime.now(), context),
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(
              title: l10n.overviewTitle,
              subtitle: l10n.adminOverviewSubtitle,
              showRule: false,
            ),
            const _OverviewStats(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.quickActionsTitle),
            const _QuickActions(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.adminManagementTitle, showRule: false),
            const _ManagementList(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.categoriesTitle, showRule: false),
            const _CategoryShortcuts(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(
              title: l10n.recentJobsTitle,
              subtitle: l10n.recentJobsSubtitle,
              showRule: false,
              trailing: TextButton(
                key: const Key('nav_jobs_all'),
                onPressed: () => context.go(AppRoutes.jobs),
                child: Text(l10n.recentJobsViewAll),
              ),
            ),
            const _RecentJobs(),
          ],
        ),
      ),
    );
  }

  /// The welcome line, using the employee's real name when the directory has
  /// one and falling back to the address only when it does not.
  static String _greeting(
    BuildContext context,
    AppUser? user,
    AppLocalizations l10n,
  ) {
    final String? name = user?.name;
    if (name != null && name.trim().isNotEmpty) {
      return l10n.welcomeNameLabel(name.trim());
    }
    final String? email = user?.email;
    if (email != null && email.trim().isNotEmpty) {
      return l10n.welcomeNameLabel(email.trim());
    }
    return l10n.welcomeAdmin;
  }
}

/// The four figures an administrator opens the app to see.
///
/// `started` is counted together with `in_progress`: both mean "the technician
/// has begun and has not finished", which is the only distinction the overview
/// needs — the exact status is one tap away in the list, and the technician
/// dashboard already buckets them the same way. `cancelled` stays out of the
/// tiles (a cancelled job is history, not work to manage) and remains reachable
/// through the jobs list filter.
///
/// The tiles are not tappable: the jobs route accepts `?category=` only, and a
/// tile that appeared to filter by status without doing so would be worse than
/// one that plainly does not.
class _OverviewStats extends StatelessWidget {
  const _OverviewStats();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final JobsCubit cubit = context.read<JobsCubit>();

        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return AppLoadingStateView(label: l10n.jobsLoadingLabel);
          case JobsStatus.failure:
            return _OverviewError(
              onRetry: cubit.loadJobs,
              retryKey: const Key('overview_retry'),
            );
          case JobsStatus.success:
            final List<Job> jobs = state.jobs;
            int countOf(String status) =>
                jobs.where((Job j) => j.status.value == status).length;

            return AppStatGrid(
              children: <Widget>[
                AppStatTile(
                  statKey: const Key('overview_total'),
                  label: l10n.totalJobsLabel,
                  value: jobs.length,
                  accent: AppColors.primary,
                ),
                AppStatTile(
                  statKey: const Key('overview_assigned'),
                  label: l10n.statusAssigned,
                  value: countOf(JobStatus.assigned),
                  accent: AppColors.info,
                ),
                AppStatTile(
                  statKey: const Key('overview_in_progress'),
                  label: l10n.statusInProgress,
                  value:
                      countOf(JobStatus.started) + countOf(JobStatus.inProgress),
                  accent: AppColors.warning,
                ),
                AppStatTile(
                  statKey: const Key('overview_completed'),
                  label: l10n.statusCompleted,
                  value: countOf(JobStatus.completed),
                  accent: AppColors.success,
                ),
              ],
            );
        }
      },
    );
  }
}

/// Shared failure surface for the two data sections on this screen.
///
/// It states that the figures could not be loaded and offers a retry; it does
/// not substitute zeros, which would read as "the business has no work".
class _OverviewError extends StatelessWidget {
  const _OverviewError({required this.onRetry, required this.retryKey});

  final VoidCallback onRetry;

  /// Each section carries its own retry key: on a failed load both the
  /// overview and the recent-jobs list fail together, and one key on two
  /// buttons would make `find.byKey` ambiguous.
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: AppStateView(
        icon: Icons.insights_outlined,
        title: l10n.dashboardOverviewErrorTitle,
        message: l10n.dashboardOverviewErrorMessage,
        action: FilledButton.tonalIcon(
          key: retryKey,
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: AppDimensions.iconMd),
          label: Text(l10n.retryButton),
        ),
      ),
    );
  }
}

/// The three frequent destinations.
///
/// "Create job" is the only filled button on the screen: one primary action per
/// screen keeps the hierarchy unambiguous. The other two are outlined and wrap
/// onto their own line on a small phone.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('nav_create_job'),
          onPressed: () => context.push(AppRoutes.jobCreate),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, AppDimensions.buttonHeight),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          ),
          icon: const Icon(Icons.add_task_outlined, size: AppDimensions.iconMd),
          label: Text(l10n.createJobButton),
        ),
        OutlinedButton.icon(
          key: const Key('nav_jobs'),
          onPressed: () => context.go(AppRoutes.jobs),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppDimensions.buttonHeight),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          ),
          icon: const Icon(
            Icons.event_note_outlined,
            size: AppDimensions.iconMd,
          ),
          label: Text(l10n.viewJobsButton),
        ),
        OutlinedButton.icon(
          key: const Key('nav_customers'),
          onPressed: () => context.push(AppRoutes.customers),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppDimensions.buttonHeight),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          ),
          icon: const Icon(
            Icons.people_outline_rounded,
            size: AppDimensions.iconMd,
          ),
          label: Text(l10n.customersTitle),
        ),
      ],
    );
  }
}

/// The two admin-only management areas, as quiet list rows.
///
/// The technician home has no counterpart, and the router refuses both routes
/// for any non-admin role; the SECURITY DEFINER RPCs behind them refuse a
/// non-admin caller regardless of the UI.
class _ManagementList extends StatelessWidget {
  const _ManagementList();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    // A Material, not a decorated Container: the ink a ListTile paints on tap
    // lands on the nearest Material ancestor, so behind a plain Container the
    // splash was drawn underneath this surface and never became visible. The
    // shape carries the same hairline border and radius the Container had.
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          ListTile(
            key: const Key('nav_admin_technicians'),
            onTap: () => context.push(AppRoutes.adminTechnicians),
            leading: const Icon(Icons.badge_outlined),
            title: Text(l10n.adminTechniciansTitle),
            subtitle: Text(l10n.adminTechniciansTileSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1, color: context.colors.outlineVariant),
          ListTile(
            key: const Key('nav_admin_customers'),
            onTap: () => context.push(AppRoutes.adminCustomers),
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(l10n.adminCustomersTitle),
            subtitle: Text(l10n.adminCustomersTileSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// Category shortcuts with their real per-category counts.
class _CategoryShortcuts extends StatelessWidget {
  const _CategoryShortcuts();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final List<Job>? jobs = state.status == JobsStatus.success
            ? state.jobs
            : null;
        final int? kitchenCount = jobs
            ?.where((Job job) => job.jobType == JobCategory.kitchenRenovation)
            .length;
        final int? homeCount = jobs
            ?.where((Job job) => job.jobType == JobCategory.homeRenovation)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DashboardCategoryCard(
              key: const Key('category_card_kitchen'),
              icon: Icons.kitchen_outlined,
              title: l10n.jobCategoryKitchenRenovation,
              jobCount: kitchenCount,
              countLabel: l10n.jobsCountLabel,
              semanticLabel:
                  '${l10n.jobCategoryKitchenRenovation}'
                  '${kitchenCount == null ? '' : ', ${l10n.jobsCountLabel(kitchenCount)}'}',
              isKitchen: true,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DashboardCategoryCard(
              key: const Key('category_card_home_renovation'),
              icon: Icons.house_siding_outlined,
              title: l10n.jobCategoryHomeRenovation,
              jobCount: homeCount,
              countLabel: l10n.jobsCountLabel,
              semanticLabel:
                  '${l10n.jobCategoryHomeRenovation}'
                  '${homeCount == null ? '' : ', ${l10n.jobsCountLabel(homeCount)}'}',
              isKitchen: false,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.homeRenovation}',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The most recently touched jobs.
///
/// Sorted by `updated_at`, newest first — the column already exists and is
/// maintained by the database, so "what moved since I last looked" needs no new
/// query and no new state. Capped at five: this is an entry point into the
/// list, not a second list.
class _RecentJobs extends StatelessWidget {
  const _RecentJobs();

  static const int _limit = 5;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        final JobsCubit cubit = context.read<JobsCubit>();

        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return AppLoadingStateView(label: l10n.jobsLoadingLabel);
          case JobsStatus.failure:
            return _OverviewError(
              onRetry: cubit.loadJobs,
              retryKey: const Key('recent_jobs_retry'),
            );
          case JobsStatus.success:
            if (state.jobs.isEmpty) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: context.colors.outlineVariant),
                ),
                child: AppEmptyStateView(
                  key: const Key('recent_jobs_empty'),
                  icon: Icons.event_note_outlined,
                  title: l10n.jobsEmptyTitle,
                  message: l10n.jobsEmptySubtitle,
                ),
              );
            }

            final List<Job> recent =
                (<Job>[...state.jobs]..sort(
                  (Job a, Job b) => b.updatedAt.compareTo(a.updatedAt),
                )).take(_limit).toList();

            // A Material so each row's ink lands on this surface.
            return Material(
              color: context.colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.card,
                side: BorderSide(color: context.colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < recent.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: AppSpacing.lg,
                        color: context.colors.outlineVariant,
                      ),
                    _RecentJobRow(job: recent[i]),
                  ],
                ],
              ),
            );
        }
      },
    );
  }
}

/// One line of [_RecentJobs]: job number, customer, who holds it, when it last
/// moved, and the status pill. Everything shown already exists on [Job].
class _RecentJobRow extends StatelessWidget {
  const _RecentJobRow({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    final String holder = (job.assignedEmployeeName ?? '').trim().isNotEmpty
        ? job.assignedEmployeeName!.trim()
        : l10n.unassignedLabel;

    return ListTile(
      key: Key('recent_job_${job.id}'),
      onTap: () => context.goNamed(
        'jobDetails',
        pathParameters: <String, String>{'id': job.id},
      ),
      contentPadding: const EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        end: AppSpacing.md,
      ),
      title: Row(
        children: <Widget>[
          Text(
            '#${job.jobNumber}',
            style: context.textStyles.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((job.customerName ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                job.customerName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodyMedium,
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpacing.xxs),
        child: Text(
          '$holder · ${formatJobDate(job.updatedAt, context)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
      trailing: JobStatusBadge(
        label: mapper.statusLabel(job.status),
        status: job.status,
      ),
    );
  }
}

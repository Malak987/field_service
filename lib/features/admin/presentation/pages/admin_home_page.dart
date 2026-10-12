import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_section_header.dart';
import 'package:field_service/core/widgets/app_state_views.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/dashboard_category_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Admin dashboard (route `/` for admin roles).
///
/// Ordered by what an administrator actually does in a day, not by widget
/// convenience:
///
/// 1. greeting — plain text, no card;
/// 2. the actions: create a job first (filled, because it is the primary
///    action), then the two places work is reviewed;
/// 3. the overview — one bordered list of the real status counts, hairline
///    separated, so six numbers stay comparable instead of becoming six
///    competing tiles;
/// 4. administration — quiet list rows for the two management areas;
/// 5. category shortcuts.
///
/// Every number comes from the shared [JobsCubit] (the same local mirror the
/// jobs list reads). On failure the overview renders nothing at all — the
/// dashboard never invents a figure.
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
            _Greeting(user: user),
            const SizedBox(height: AppSpacing.xl),
            AppSectionHeader(title: l10n.quickActionsTitle),
            const _QuickActions(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.overviewTitle),
            const _OverviewList(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.adminManagementTitle),
            const _ManagementList(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.categoriesTitle),
            const _CategoryShortcuts(),
          ],
        ),
      ),
    );
  }
}

/// The welcome line — open text on the canvas.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AppUser? user;

  String get _displayName {
    final String? name = user?.name;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return user?.email ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _displayName.isNotEmpty
              ? l10n.welcomeNameLabel(_displayName)
              : l10n.welcomeAdmin,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.roleAdminLabel,
          style: context.textStyles.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
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

/// The real-data overview as a compact list.
///
/// Six numbers side by side as tiles turned into a wall of coloured boxes that
/// all shouted equally. As hairline-separated rows in one surface they can be
/// read top to bottom in a second, and the status colour is a dot next to the
/// label — never the only carrier of the meaning.
class _OverviewList extends StatelessWidget {
  const _OverviewList();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return AppLoadingStateView(label: l10n.jobsLoadingLabel);
          case JobsStatus.failure:
            // No invented numbers: the overview simply stays hidden.
            return const SizedBox.shrink();
          case JobsStatus.success:
            final List<Job> jobs = state.jobs;
            int countOf(String status) =>
                jobs.where((Job j) => j.status.value == status).length;

            final List<_OverviewEntry> rows = <_OverviewEntry>[
              _OverviewEntry(
                rowKey: const Key('overview_total'),
                label: l10n.totalJobsLabel,
                value: jobs.length,
                color: AppColors.primary,
              ),
              _OverviewEntry(
                rowKey: const Key('overview_assigned'),
                label: l10n.statusAssigned,
                value: countOf(JobStatus.assigned),
                color: AppColors.info,
              ),
              _OverviewEntry(
                rowKey: const Key('overview_started'),
                label: l10n.statusStarted,
                value: countOf(JobStatus.started),
                color: AppColors.goldDeep,
              ),
              _OverviewEntry(
                rowKey: const Key('overview_in_progress'),
                label: l10n.statusInProgress,
                value: countOf(JobStatus.inProgress),
                color: AppColors.primaryDark,
              ),
              _OverviewEntry(
                rowKey: const Key('overview_completed'),
                label: l10n.statusCompleted,
                value: countOf(JobStatus.completed),
                color: AppColors.success,
              ),
              _OverviewEntry(
                rowKey: const Key('overview_cancelled'),
                label: l10n.statusCancelled,
                value: countOf(JobStatus.cancelled),
                color: AppColors.error,
              ),
            ];

            return Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: AppRadius.card,
                border: Border.all(color: context.colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < rows.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: AppSpacing.lg,
                        color: context.colors.outlineVariant,
                      ),
                    _OverviewRow(entry: rows[i]),
                  ],
                ],
              ),
            );
        }
      },
    );
  }
}

/// One row of [_OverviewList]. The [Key] lives on the row so the dashboard
/// tests can read a single figure without depending on the layout around it.
class _OverviewEntry {
  const _OverviewEntry({
    required this.rowKey,
    required this.label,
    required this.value,
    required this.color,
  });

  final Key rowKey;
  final String label;
  final int value;
  final Color color;
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.entry});

  final _OverviewEntry entry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: entry.rowKey,
      label: '${entry.label}: ${entry.value}',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.color,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${entry.value}',
              style: context.textStyles.titleMedium?.copyWith(
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ),
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

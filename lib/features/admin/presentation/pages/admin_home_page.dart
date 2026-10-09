import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
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
import 'package:field_service/features/jobs/presentation/widgets/dashboard_category_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Admin home (route `/` for admin roles).
///
/// A compact dashboard, not a menu: a personalised header, a real-data
/// overview of the loaded jobs, the two job categories as large shortcuts
/// and the existing quick actions. All numbers come from the already-loaded
/// jobs list — nothing is invented; while jobs load the overview shows a
/// progress line, and on failure it simply stays out of the way.
class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminDashboardTitle),
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
      bottomNavigationBar: const AppBottomNav(isAdmin: true, selectedIndex: 0),
      body: BlocProvider<JobsCubit>(
        // The SAME shared cubit pattern the jobs list uses — the overview
        // shows what the backend/local mirror actually knows.
        create: (_) => sl<JobsCubit>()..loadJobs(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppSpacing.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _HeaderCard(user: user),
                const SizedBox(height: AppSpacing.xl),
                // Quick actions FIRST: they are the admin's most frequent
                // taps and must stay visible without scrolling on small
                // screens (and in the default-size widget test surface).
                _SectionTitle(label: l10n.quickActionsTitle),
                const SizedBox(height: AppSpacing.md),
                // The admin's existing navigation, unchanged in behaviour:
                // Jobs replaces the stack (`go`); Customers and Create Job
                // are pushed so their Back buttons return here.
                HomeNavigationTile(
                  key: const Key('nav_jobs'),
                  icon: Icons.event_note_outlined,
                  label: l10n.viewJobsButton,
                  onTap: () => context.go(AppRoutes.jobs),
                ),
                const SizedBox(height: AppSpacing.md),
                HomeNavigationTile(
                  key: const Key('nav_customers'),
                  icon: Icons.people_outline,
                  label: l10n.customersTitle,
                  onTap: () => context.push(AppRoutes.customers),
                ),
                const SizedBox(height: AppSpacing.md),
                HomeNavigationTile(
                  key: const Key('nav_create_job'),
                  icon: Icons.add_task_outlined,
                  label: l10n.createJobButton,
                  onTap: () => context.push(AppRoutes.jobCreate),
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionTitle(label: l10n.overviewTitle),
                const SizedBox(height: AppSpacing.md),
                const _OverviewCard(),
                const SizedBox(height: AppSpacing.xl),
                _SectionTitle(label: l10n.categoriesTitle),
                const SizedBox(height: AppSpacing.md),
                BlocBuilder<JobsCubit, JobsState>(
                  builder: (BuildContext context, JobsState state) {
                    final List<Job>? jobs = state.status == JobsStatus.success
                        ? state.jobs
                        : null;
                    final int? kitchenCount = jobs?.where((Job job) =>
                        job.jobType == JobCategory.kitchenRenovation).length;
                    final int? homeCount = jobs?.where((Job job) =>
                        job.jobType == JobCategory.homeRenovation).length;
                    return Column(
                      children: <Widget>[
                        DashboardCategoryCard(
                          key: const Key('category_card_kitchen'),
                          icon: Icons.kitchen_outlined,
                          title: l10n.jobCategoryKitchenRenovation,
                          jobCount: kitchenCount,
                          countLabel: l10n.jobsCountLabel,
                          semanticLabel: '${l10n.jobCategoryKitchenRenovation}${kitchenCount == null ? '' : ', ${l10n.jobsCountLabel(kitchenCount)}'}',
                          isKitchen: true,
                          onTap: () => context.go('${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DashboardCategoryCard(
                          key: const Key('category_card_home_renovation'),
                          icon: Icons.house_siding_outlined,
                          title: l10n.jobCategoryHomeRenovation,
                          jobCount: homeCount,
                          countLabel: l10n.jobsCountLabel,
                          semanticLabel: '${l10n.jobCategoryHomeRenovation}, ${homeCount == null ? '' : l10n.jobsCountLabel(homeCount)}',
                          isKitchen: false,
                          onTap: () => context.go('${AppRoutes.jobs}?category=${JobCategory.homeRenovation}'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section heading used between the dashboard blocks.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

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

/// Personalised header: avatar (initials of the REAL employee name or the
/// e-mail — no fake identities), welcome line and role.
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
                      l10n.welcomeAdmin,
                      style: context.textStyles.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.roleAdminLabel,
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.admin_panel_settings_outlined,
              size: AppDimensions.iconXl,
              color: AppColors.goldAccent,
            ),
          ],
        ),
      ),
    );
  }
}

/// The real-data overview: total and known status distribution from loaded
/// jobs. Shows a progress line while loading and renders nothing on
/// failure — the dashboard never invents numbers.
class _OverviewCard extends StatelessWidget {
  const _OverviewCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      builder: (BuildContext context, JobsState state) {
        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: SizedBox(
                    width: AppDimensions.buttonSpinnerSize,
                    height: AppDimensions.buttonSpinnerSize,
                    child: const CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            );
          case JobsStatus.failure:
            // No invented numbers: the overview simply stays hidden.
            return const SizedBox.shrink();
          case JobsStatus.success:
            final List<Job> jobs = state.jobs;
            final int assigned = jobs
                .where((Job j) => j.status.value == JobStatus.assigned)
                .length;
            final int started = jobs
                .where((Job j) => j.status.value == JobStatus.started)
                .length;
            final int inProgress = jobs
                .where((Job j) => j.status.value == JobStatus.inProgress)
                .length;
            final int completed = jobs
                .where((Job j) => j.status.value == JobStatus.completed)
                .length;
            final int cancelled = jobs
                .where((Job j) => j.status.value == JobStatus.cancelled)
                .length;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double tileWidth =
                        ((constraints.maxWidth - AppSpacing.sm) / 2).clamp(
                          140.0,
                          220.0,
                        ).toDouble();
                    return Align(
                      alignment: AlignmentDirectional.center,
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: <Widget>[
                          _StatTile(
                            key: const Key('overview_total'),
                            value: jobs.length,
                            label: l10n.totalJobsLabel,
                            color: AppColors.primary,
                            icon: Icons.work_outline_rounded,
                            width: tileWidth,
                          ),
                          _StatTile(
                            key: const Key('overview_assigned'),
                            value: assigned,
                            label: l10n.statusAssigned,
                            color: AppColors.info,
                            icon: Icons.assignment_ind_outlined,
                            width: tileWidth,
                          ),
                          _StatTile(
                            key: const Key('overview_started'),
                            value: started,
                            label: l10n.statusStarted,
                            color: AppColors.goldDeep,
                            icon: Icons.play_circle_outline_rounded,
                            width: tileWidth,
                          ),
                          _StatTile(
                            key: const Key('overview_in_progress'),
                            value: inProgress,
                            label: l10n.statusInProgress,
                            color: AppColors.primaryDark,
                            icon: Icons.handyman_outlined,
                            width: tileWidth,
                          ),
                          _StatTile(
                            key: const Key('overview_completed'),
                            value: completed,
                            label: l10n.statusCompleted,
                            color: AppColors.success,
                            icon: Icons.task_alt_rounded,
                            width: tileWidth,
                          ),
                          _StatTile(
                            key: const Key('overview_cancelled'),
                            value: cancelled,
                            label: l10n.statusCancelled,
                            color: AppColors.error,
                            icon: Icons.cancel_outlined,
                            width: tileWidth,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
        }
      },
    );
  }
}

/// One compact, readable status tile in the admin overview.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
    required this.width,
  });

  final int value;
  final String label;
  final Color color;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        label: '$label: $value',
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: BorderDirectional(
              start: BorderSide(color: color, width: 3),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppDimensions.iconSm, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$value',
                      maxLines: 1,
                      style: context.textStyles.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

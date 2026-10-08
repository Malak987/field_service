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
                _CategoryCard(
                  key: const Key('category_card_kitchen'),
                  icon: Icons.kitchen_outlined,
                  title: l10n.jobCategoryKitchenRenovation,
                  category: JobCategory.kitchenRenovation,
                ),
                const SizedBox(height: AppSpacing.md),
                _CategoryCard(
                  key: const Key('category_card_home_renovation'),
                  icon: Icons.house_siding_outlined,
                  title: l10n.jobCategoryHomeRenovation,
                  category: JobCategory.homeRenovation,
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
    final bool isDark = context.isDarkMode;

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
                color: isDark
                    ? AppColors.primarySurfaceDark
                    : AppColors.primarySurfaceLight,
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
                      style: context.textStyles.titleLarge,
                    )
                  else
                    Text(
                      l10n.welcomeAdmin,
                      style: context.textStyles.titleLarge,
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
              color: isDark
                  ? AppColors.goldAccentDarkVariant
                  : AppColors.goldAccent,
            ),
          ],
        ),
      ),
    );
  }
}

/// The real-data overview: total / in progress / completed from the loaded
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
            final int inProgress = jobs
                .where((Job j) => j.status.value == JobStatus.inProgress)
                .length;
            final int completed = jobs
                .where((Job j) => j.status.value == JobStatus.completed)
                .length;
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: <Widget>[
                    _StatTile(
                      key: const Key('overview_assigned'),
                      value: assigned,
                      label: l10n.statusAssigned,
                      color: context.colors.primary,
                    ),
                    _StatTile(
                      key: const Key('overview_in_progress'),
                      value: inProgress,
                      label: l10n.statusInProgress,
                      color: AppColors.warning,
                    ),
                    _StatTile(
                      key: const Key('overview_completed'),
                      value: completed,
                      label: l10n.statusCompleted,
                      color: AppColors.success,
                    ),
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}

/// One number + label inside the overview card.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: context.textStyles.headlineMedium?.copyWith(color: color),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two job categories as a large, touch-friendly shortcut into
/// the filtered jobs list (existing route, client-side category filter).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.category,
  });

  final IconData icon;
  final String title;
  final String category;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool isDark = context.isDarkMode;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('${AppRoutes.jobs}?category=$category'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Container(
                width: AppDimensions.iconXl,
                height: AppDimensions.iconXl,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.goldSurfaceDark
                      : AppColors.goldSurfaceLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: AppDimensions.iconMd,
                  color: isDark
                      ? AppColors.goldAccentDarkVariant
                      : AppColors.goldDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: context.textStyles.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    BlocBuilder<JobsCubit, JobsState>(
                      builder: (BuildContext context, JobsState state) {
                        if (state.status != JobsStatus.success) {
                          return const SizedBox.shrink();
                        }
                        final int count = state.jobs
                            .where((Job j) => j.jobType == category)
                            .length;
                        return Text(
                          l10n.jobsCountLabel(count),
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimensions.iconLg,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

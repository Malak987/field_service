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
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_section_header.dart';
import 'package:field_service/core/widgets/app_state_views.dart';
import 'package:field_service/core/widgets/app_status_badge.dart';
import 'package:field_service/core/widgets/app_surface_panel.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The administrator's operational home.
///
/// The page is arranged around the decisions an administrator makes first:
/// create work, understand the live workload, then move into a category,
/// recent job or management area. It reads the existing local jobs mirror and
/// only turns existing values into a clearer hierarchy; no query, permission or
/// workflow rule is introduced here.
class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isWide =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobs(),
      child: AppPageBody(
        wide: isWide,
        responsivePadding: true,
        appBar: const _AdminHomeAppBar(),
        navigation: const AppNavSpec(isAdmin: true, selectedIndex: 0),
        child: _AdminDashboard(isWide: isWide),
      ),
    );
  }
}

/// Keeps account access and the existing sign-out flow in the page chrome.
class _AdminHomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AdminHomeAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return AppBar(
      title: Text(l10n.adminDashboardTitle),
      actions: <Widget>[
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
          icon: const Icon(Icons.logout_outlined, size: AppDimensions.iconMd),
          onPressed: isLoading
              ? null
              : () => context.read<AuthenticationCubit>().signOut(),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AdminWelcomeHero(onCreateJob: () => _createJobAndRefresh(context)),
        const SizedBox(height: AppSpacing.xxxl),
        const _QuickActionsSection(),
        const SizedBox(height: AppSpacing.xxxl),
        BlocBuilder<JobsCubit, JobsState>(
          builder: (BuildContext context, JobsState state) {
            final JobsCubit cubit = context.read<JobsCubit>();

            switch (state.status) {
              case JobsStatus.initial:
              case JobsStatus.loading:
                return const _DashboardLoadingContent();
              case JobsStatus.failure:
                return _DashboardFailureContent(onRetry: cubit.loadJobs);
              case JobsStatus.success:
                return _DashboardDataContent(
                  jobs: state.jobs,
                  isWide: isWide,
                  onCreateJob: () => _createJobAndRefresh(context),
                );
            }
          },
        ),
      ],
    );
  }

  /// Uses the original create route and refreshes this page's existing cubit
  /// when the form returns. The form still owns all creation and offline-sync
  /// behaviour; the dashboard merely picks up its local result.
  Future<void> _createJobAndRefresh(BuildContext context) async {
    final JobsCubit cubit = context.read<JobsCubit>();
    await context.push(AppRoutes.jobCreate);
    if (context.mounted) {
      cubit.loadJobs();
    }
  }
}

/// The branded first impression: the real Heimwerk mark, a real employee name,
/// the localized date and the one primary action on this screen.
class _AdminWelcomeHero extends StatelessWidget {
  const _AdminWelcomeHero({required this.onCreateJob});

  final VoidCallback onCreateJob;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<AuthenticationCubit, AuthenticationState>(
      buildWhen: (AuthenticationState previous, AuthenticationState current) =>
          previous.user != current.user,
      builder: (BuildContext context, AuthenticationState state) {
        final String greeting = _greeting(state.user, l10n);

        return Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: context.colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool useHorizontalLayout =
                    constraints.maxWidth >= AppDimensions.tabletBreakpoint;
                final Widget brand = _BrandMark(label: l10n.appName);
                final Widget message = _WelcomeMessage(
                  greeting: greeting,
                  roleLabel: l10n.roleAdminLabel,
                  dateLabel: formatFullDate(DateTime.now(), context),
                );
                final Widget action = SizedBox(
                  width: useHorizontalLayout ? 188 : double.infinity,
                  child: FilledButton.icon(
                    key: const Key('nav_create_job'),
                    onPressed: onCreateJob,
                    icon: const Icon(
                      Icons.add_task_outlined,
                      size: AppDimensions.iconMd,
                    ),
                    label: Text(l10n.createJobButton),
                  ),
                );

                if (!useHorizontalLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          brand,
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: message),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      action,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    brand,
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: message),
                    const SizedBox(width: AppSpacing.xl),
                    action,
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  static String _greeting(AppUser? user, AppLocalizations l10n) {
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

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: 68,
          height: 68,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: const BoxDecoration(
            color: AppColors.goldSurface,
            borderRadius: AppRadius.logoBadge,
          ),
          child: Image.asset(AuthLogo.assetName, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _WelcomeMessage extends StatelessWidget {
  const _WelcomeMessage({
    required this.greeting,
    required this.roleLabel,
    required this.dateLabel,
  });

  final String greeting;
  final String roleLabel;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppStatusBadge(
          icon: Icons.workspace_premium_outlined,
          label: roleLabel,
          tone: AppStatusTone.brand,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          greeting,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Icon(
              Icons.calendar_today_outlined,
              size: AppDimensions.iconSm,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Secondary navigation is intentionally grouped in one quiet panel. It keeps
/// creation, jobs and customers within a thumb reach without competing with the
/// hero's primary job action.
class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: l10n.quickActionsTitle, showRule: false),
        AppSurfacePanel(
          divideRows: false,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _QuickActionGrid(
                children: <Widget>[
                  _QuickActionTile(
                    key: const Key('nav_create_customer'),
                    icon: Icons.person_add_alt_1_outlined,
                    label: l10n.addCustomer,
                    onTap: () => context.push(AppRoutes.customerCreate),
                  ),
                  _QuickActionTile(
                    key: const Key('nav_jobs'),
                    icon: Icons.event_note_outlined,
                    label: l10n.viewJobsButton,
                    onTap: () => context.go(AppRoutes.jobs),
                  ),
                  _QuickActionTile(
                    key: const Key('nav_customers'),
                    icon: Icons.people_outline_rounded,
                    label: l10n.customersTitle,
                    onTap: () => context.push(AppRoutes.customers),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= AppDimensions.desktopBreakpoint
            ? 3
            : constraints.maxWidth >= AppDimensions.tabletBreakpoint
            ? 2
            : 1;
        final double gap = AppSpacing.sm;
        final double itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.control,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: AppDimensions.buttonHeightCompact,
                    height: AppDimensions.buttonHeightCompact,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: AppRadius.banner,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: AppDimensions.iconMd,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: AppDimensions.iconMd,
                    color: context.colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single state frame for every data-dependent part of the dashboard.
/// Loading and failure never render misleading zero counters, stale category
/// counts or a duplicated error for the same failed request.
class _DashboardLoadingContent extends StatelessWidget {
  const _DashboardLoadingContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSurfacePanel(
          divideRows: false,
          children: <Widget>[
            AppLoadingStateView(label: context.l10n.jobsLoadingLabel),
          ],
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _ManagementSection(),
      ],
    );
  }
}

class _DashboardFailureContent extends StatelessWidget {
  const _DashboardFailureContent({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSurfacePanel(
          divideRows: false,
          children: <Widget>[
            AppErrorStateView(
              title: l10n.dashboardOverviewErrorTitle,
              message: l10n.dashboardOverviewErrorMessage,
              retryLabel: l10n.retryButton,
              onRetry: onRetry,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _ManagementSection(),
      ],
    );
  }
}

class _DashboardDataContent extends StatelessWidget {
  const _DashboardDataContent({
    required this.jobs,
    required this.isWide,
    required this.onCreateJob,
  });

  final List<Job> jobs;
  final bool isWide;
  final VoidCallback onCreateJob;

  @override
  Widget build(BuildContext context) {
    final Widget overview = _OverviewSection(jobs: jobs);
    final Widget categories = _CategorySection(jobs: jobs);
    final Widget recent = _RecentJobsSection(
      jobs: jobs,
      onCreateJob: onCreateJob,
    );
    const Widget management = _ManagementSection();

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          overview,
          const SizedBox(height: AppSpacing.xxxl),
          categories,
          const SizedBox(height: AppSpacing.xxxl),
          recent,
          const SizedBox(height: AppSpacing.xxxl),
          management,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        overview,
        const SizedBox(height: AppSpacing.xxxl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 3, child: recent),
            const SizedBox(width: AppSpacing.xxl),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  categories,
                  const SizedBox(height: AppSpacing.xxxl),
                  management,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The summary is one information surface instead of a row of unrelated cards:
/// the total anchors the panel and the three operational states scan below it.
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.jobs});

  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final int assigned = _count(JobStatus.assigned);
    final int inProgress =
        _count(JobStatus.started) + _count(JobStatus.inProgress);
    final int completed = _count(JobStatus.completed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          title: l10n.overviewTitle,
          subtitle: l10n.adminOverviewSubtitle,
          showRule: false,
        ),
        Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: context.colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TotalJobsMetric(value: jobs.length, label: l10n.totalJobsLabel),
                const SizedBox(height: AppSpacing.lg),
                Divider(height: 1, color: context.colors.outlineVariant),
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (
                    BuildContext context,
                    BoxConstraints constraints,
                  ) {
                    final bool isThreeColumn =
                        constraints.maxWidth >= AppDimensions.tabletBreakpoint;
                    final List<_OverviewMetric> metrics = <_OverviewMetric>[
                      _OverviewMetric(
                        key: const Key('overview_assigned'),
                        label: l10n.statusAssigned,
                        value: assigned,
                        accent: AppColors.info,
                      ),
                      _OverviewMetric(
                        key: const Key('overview_in_progress'),
                        label: l10n.statusInProgress,
                        value: inProgress,
                        accent: AppColors.warning,
                      ),
                      _OverviewMetric(
                        key: const Key('overview_completed'),
                        label: l10n.statusCompleted,
                        value: completed,
                        accent: AppColors.success,
                      ),
                    ];

                    if (isThreeColumn) {
                      return Row(
                        children: <Widget>[
                          for (int index = 0; index < metrics.length; index++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsetsDirectional.only(
                                  end: index < metrics.length - 1
                                      ? AppSpacing.md
                                      : 0,
                                ),
                                child: metrics[index],
                              ),
                            ),
                        ],
                      );
                    }

                    final double itemWidth =
                        (constraints.maxWidth - AppSpacing.sm) / 2;
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final _OverviewMetric metric in metrics)
                          SizedBox(width: itemWidth, child: metric),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _count(String status) =>
      jobs.where((Job job) => job.status.value == status).length;
}

class _TotalJobsMetric extends StatelessWidget {
  const _TotalJobsMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('overview_total'),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: AppRadius.banner,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: AppDimensions.iconXl,
            height: AppDimensions.iconXl,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.assignment_outlined,
              color: AppColors.primary,
              size: AppDimensions.iconLg,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: context.textStyles.titleMedium?.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '$value',
            style: context.textStyles.headlineSmall?.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.md,
        end: AppSpacing.sm,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            maxLines: 1,
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

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.jobs});

  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final int kitchenCount = jobs
        .where((Job job) => job.jobType == JobCategory.kitchenRenovation)
        .length;
    final int homeCount = jobs
        .where((Job job) => job.jobType == JobCategory.homeRenovation)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: l10n.categoriesTitle, showRule: false),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool useTwoColumns =
                constraints.maxWidth >= AppDimensions.tabletBreakpoint;
            final Widget kitchen = _AdminCategoryCard(
              key: const Key('category_card_kitchen'),
              icon: Icons.kitchen_outlined,
              title: l10n.jobCategoryKitchenRenovation,
              countLabel: l10n.jobsCountLabel(kitchenCount),
              count: kitchenCount,
              accent: AppColors.primary,
              wash: AppColors.primarySurface,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}',
              ),
            );
            final Widget home = _AdminCategoryCard(
              key: const Key('category_card_home_renovation'),
              icon: Icons.house_siding_outlined,
              title: l10n.jobCategoryHomeRenovation,
              countLabel: l10n.jobsCountLabel(homeCount),
              count: homeCount,
              accent: AppColors.goldDeep,
              wash: AppColors.goldSurface,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.homeRenovation}',
              ),
            );

            if (!useTwoColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  kitchen,
                  const SizedBox(height: AppSpacing.sm),
                  home,
                ],
              );
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: kitchen),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: home),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AdminCategoryCard extends StatelessWidget {
  const _AdminCategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.count,
    required this.accent,
    required this.wash,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String countLabel;
  final int count;
  final Color accent;
  final Color wash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $countLabel',
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: context.colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 160),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: AppDimensions.iconXl,
                        height: AppDimensions.iconXl,
                        decoration: BoxDecoration(
                          color: wash,
                          borderRadius: AppRadius.banner,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: AppDimensions.iconLg,
                          color: accent,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: AppDimensions.iconMd,
                        color: accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      Text(
                        '$count',
                        style: context.textStyles.titleLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          countLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentJobsSection extends StatelessWidget {
  const _RecentJobsSection({required this.jobs, required this.onCreateJob});

  static const int _limit = 5;

  final List<Job> jobs;
  final VoidCallback onCreateJob;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
        if (jobs.isEmpty)
          AppSurfacePanel(
            divideRows: false,
            children: <Widget>[
              AppEmptyStateView(
                key: const Key('recent_jobs_empty'),
                icon: Icons.event_note_outlined,
                title: l10n.jobsEmptyTitle,
                message: l10n.jobsEmptySubtitle,
                action: FilledButton.icon(
                  key: const Key('create_first_job_button'),
                  onPressed: onCreateJob,
                  icon: const Icon(Icons.add_rounded, size: AppDimensions.iconMd),
                  label: Text(l10n.createFirstJobButton),
                ),
              ),
            ],
          )
        else
          AppSurfacePanel(
            children: <Widget>[
              for (final Job job in _recentJobs())
                JobsListItem(
                  key: Key('recent_job_${job.id}'),
                  job: job,
                  showAssignedTechnician: true,
                  onTap: () => context.goNamed(
                    'jobDetails',
                    pathParameters: <String, String>{'id': job.id},
                  ),
                ),
            ],
          ),
      ],
    );
  }

  List<Job> _recentJobs() => (<Job>[...jobs]
        ..sort((Job a, Job b) => b.updatedAt.compareTo(a.updatedAt)))
      .take(_limit)
      .toList();
}

class _ManagementSection extends StatelessWidget {
  const _ManagementSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: l10n.adminManagementTitle, showRule: false),
        AppSurfacePanel(
          children: <Widget>[
            ListTile(
              key: const Key('nav_admin_technicians'),
              onTap: () => context.push(AppRoutes.adminTechnicians),
              leading: const Icon(Icons.badge_outlined),
              title: Text(l10n.adminTechniciansTitle),
              subtitle: Text(l10n.adminTechniciansTileSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
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
      ],
    );
  }
}

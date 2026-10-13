import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/sync/sync_status.dart';
import 'package:field_service/core/sync/sync_status_cubit.dart';
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
import 'package:field_service/core/widgets/app_sync_status_badge.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/dashboard_category_card.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_status_badge.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The technician's operational dashboard.
///
/// It is deliberately built around the next real piece of work: a technician
/// sees their own connection state, the current/next job and the remainder of
/// their queue before secondary navigation. Existing cubits, role-scoped data
/// and workflow routes remain the source of every decision on this page.
class TechnicianHomePage extends StatelessWidget {
  const TechnicianHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isWide =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<JobsCubit>(create: (_) => sl<JobsCubit>()..loadJobs()),
        BlocProvider<SyncStatusCubit>(create: (_) => sl<SyncStatusCubit>()),
      ],
      child: AppPageBody(
        wide: isWide,
        responsivePadding: true,
        appBar: const _TechnicianAppBar(),
        navigation: const AppNavSpec(isAdmin: false, selectedIndex: 0),
        child: _TechnicianDashboard(isWide: isWide),
      ),
    );
  }
}

class _TechnicianAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TechnicianAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return AppBar(
      title: Text(l10n.technicianHomeTitle),
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

class _TechnicianDashboard extends StatelessWidget {
  const _TechnicianDashboard({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TechnicianHero(),
        const SizedBox(height: AppSpacing.xl),
        const _TechnicianQuickActions(),
        const SizedBox(height: AppSpacing.xxxl),
        BlocBuilder<JobsCubit, JobsState>(
          buildWhen: _jobsSnapshotChanged,
          builder: (BuildContext context, JobsState state) {
            final JobsCubit cubit = context.read<JobsCubit>();

            return switch (state.status) {
              JobsStatus.initial || JobsStatus.loading => _JobsUnavailableLayout(
                isWide: isWide,
                main: AppSurfacePanel(
                  divideRows: false,
                  children: <Widget>[
                    AppLoadingStateView(label: context.l10n.jobsLoadingLabel),
                  ],
                ),
              ),
              JobsStatus.failure => _JobsUnavailableLayout(
                isWide: isWide,
                main: _JobsFailurePanel(onRetry: cubit.loadJobs),
              ),
              JobsStatus.success => _TechnicianWorkContent(
                jobs: state.jobs,
                isWide: isWide,
              ),
            };
          },
        ),
      ],
    );
  }
}

/// A workday header with the real Heimwerk mark, authenticated employee name
/// and the current sync fact. The sync chip is deliberately in the first
/// viewport: offline work must be visible, not hidden behind settings.
class _TechnicianHero extends StatelessWidget {
  const _TechnicianHero();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<AuthenticationCubit, AuthenticationState>(
      buildWhen: (AuthenticationState previous, AuthenticationState current) =>
          previous.user != current.user,
      builder: (BuildContext context, AuthenticationState state) {
        final Widget mark = _HeimwerkMark(label: l10n.appName);
        final Widget identity = _TechnicianIdentity(
          greeting: _greeting(state.user, l10n),
          roleLabel: l10n.roleTechnicianLabel,
          dateLabel: formatFullDate(DateTime.now(), context),
        );

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

                if (!useHorizontalLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          mark,
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: identity),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Divider(height: 1, color: context.colors.outlineVariant),
                      const SizedBox(height: AppSpacing.md),
                      const _ConnectionStatus(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    mark,
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: identity),
                    const SizedBox(width: AppSpacing.xxl),
                    const _ConnectionStatus(),
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
    return l10n.welcomeTechnician;
  }
}

class _HeimwerkMark extends StatelessWidget {
  const _HeimwerkMark({required this.label});

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

class _TechnicianIdentity extends StatelessWidget {
  const _TechnicianIdentity({
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
          icon: Icons.handyman_outlined,
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

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncStatusCubit, SyncHealth>(
      builder: (BuildContext context, SyncHealth health) => Align(
        key: const Key('tech_connection_status'),
        alignment: AlignmentDirectional.centerStart,
        child: AppSyncStatusBadge(health: health, filled: true),
      ),
    );
  }
}

/// Existing routes, restyled as two compact navigation tiles. They stay outside
/// the jobs state so a technician can create a customer/job or open the full
/// list while the local mirror is loading or unavailable.
class _TechnicianQuickActions extends StatelessWidget {
  const _TechnicianQuickActions();

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
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool useTwoColumns =
                      constraints.maxWidth >= AppDimensions.tabletBreakpoint;
                  final Widget create = _TechnicianActionTile(
                    key: const Key('nav_create_customer_job'),
                    icon: Icons.person_add_alt_1_outlined,
                    label: l10n.technicianCreateJobEntryTitle,
                    onTap: () => context.push(AppRoutes.jobTechnicianCreate),
                  );
                  final Widget jobs = _TechnicianActionTile(
                    key: const Key('nav_jobs'),
                    icon: Icons.event_note_outlined,
                    label: l10n.viewJobsButton,
                    onTap: () => context.go(AppRoutes.jobs),
                  );

                  if (!useTwoColumns) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        create,
                        const SizedBox(height: AppSpacing.sm),
                        jobs,
                      ],
                    );
                  }

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(child: create),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: jobs),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TechnicianActionTile extends StatelessWidget {
  const _TechnicianActionTile({
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

/// Common layout for loading/failure. Categories remain usable but never show
/// made-up figures when the job snapshot is unavailable.
class _JobsUnavailableLayout extends StatelessWidget {
  const _JobsUnavailableLayout({required this.isWide, required this.main});

  final bool isWide;
  final Widget main;

  @override
  Widget build(BuildContext context) {
    const Widget categories = _TechnicianCategories();

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          main,
          const SizedBox(height: AppSpacing.xxxl),
          categories,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 3, child: main),
        const SizedBox(width: AppSpacing.xxl),
        const Expanded(flex: 2, child: categories),
      ],
    );
  }
}

class _JobsFailurePanel extends StatelessWidget {
  const _JobsFailurePanel({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppSurfacePanel(
      divideRows: false,
      children: <Widget>[
        AppErrorStateView(
          title: l10n.dashboardOverviewErrorTitle,
          message: l10n.dashboardOverviewErrorMessage,
          retryLabel: l10n.retryButton,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class _TechnicianWorkContent extends StatelessWidget {
  const _TechnicianWorkContent({required this.jobs, required this.isWide});

  final List<Job> jobs;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final Widget overview = _TechnicianOverview(jobs: jobs);
    final Widget work = _TechnicianWorkArea(jobs: jobs);
    final Widget categories = _TechnicianCategories(jobs: jobs);

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          overview,
          const SizedBox(height: AppSpacing.xxxl),
          work,
          const SizedBox(height: AppSpacing.xxxl),
          categories,
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
            Expanded(flex: 3, child: work),
            const SizedBox(width: AppSpacing.xxl),
            Expanded(flex: 2, child: categories),
          ],
        ),
      ],
    );
  }
}

/// A unified job snapshot. The completed count remains present because it is a
/// real part of the technician's queue history, but it never competes with the
/// current and assigned figures above the work list.
class _TechnicianOverview extends StatelessWidget {
  const _TechnicianOverview({required this.jobs});

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
          subtitle: l10n.technicianOverviewSubtitle,
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
                    final List<_TechnicianMetric> metrics =
                        <_TechnicianMetric>[
                          _TechnicianMetric(
                            key: const Key('tech_overview_assigned'),
                            label: l10n.statusAssigned,
                            value: assigned,
                            accent: AppColors.info,
                          ),
                          _TechnicianMetric(
                            key: const Key('tech_overview_in_progress'),
                            label: l10n.statusInProgress,
                            value: inProgress,
                            accent: AppColors.warning,
                          ),
                          _TechnicianMetric(
                            key: const Key('tech_overview_completed'),
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
                        for (final _TechnicianMetric metric in metrics)
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
      key: const Key('tech_overview_total'),
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

class _TechnicianMetric extends StatelessWidget {
  const _TechnicianMetric({
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

/// Groups the currently active/next job and the remaining accessible jobs
/// without manufacturing an assignment order. A running job is featured first;
/// otherwise the already-existing oldest-assigned choice becomes the next job.
class _TechnicianWorkArea extends StatelessWidget {
  const _TechnicianWorkArea({required this.jobs});

  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    if (jobs.isEmpty) {
      return const _NoAssignedJobs();
    }

    final List<Job> active = jobs
        .where(
          (Job job) =>
              job.status.value == JobStatus.started ||
              job.status.value == JobStatus.inProgress,
        )
        .toList();
    final List<Job> assigned = jobs
        .where((Job job) => job.status.value == JobStatus.assigned)
        .toList();
    final List<Job> history = jobs
        .where(
          (Job job) =>
              job.status.value != JobStatus.started &&
              job.status.value != JobStatus.inProgress &&
              job.status.value != JobStatus.assigned,
        )
        .toList()
      ..sort((Job a, Job b) => b.updatedAt.compareTo(a.updatedAt));

    Job? focus;
    if (active.isNotEmpty) {
      // Preserve repository order for an already-running task; it is the
      // existing dashboard's first current item rather than an invented rule.
      focus = active.first;
    } else if (assigned.isNotEmpty) {
      // Do not pass the typed helper directly to `reduce`: repositories that
      // expose a JobModel subtype retain that runtime list type, and List.reduce
      // then rejects a `(Job, Job) => Job` tear-off. A normal loop keeps the
      // existing oldest-assigned presentation rule without narrowing that list.
      Job oldest = assigned.first;
      for (int index = 1; index < assigned.length; index++) {
        oldest = _longerWaiting(oldest, assigned[index]);
      }
      focus = oldest;
    }

    final List<Job> queue = <Job>[
      for (final Job job in active)
        if (job.id != focus?.id) job,
      for (final Job job in assigned)
        if (job.id != focus?.id) job,
      ...history,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (focus != null) ...<Widget>[
          AppSectionHeader(
            title: focus.status.value == JobStatus.assigned
                ? l10n.nextJobTitle
                : l10n.currentJobTitle,
            showRule: false,
          ),
          _FocusJobCard(job: focus),
        ],
        if (queue.isNotEmpty) ...<Widget>[
          if (focus != null) const SizedBox(height: AppSpacing.xxl),
          AppSectionHeader(
            title: l10n.myJobsTitle,
            showRule: false,
          ),
          AppSurfacePanel(
            children: <Widget>[
              for (final Job job in queue)
                JobsListItem(
                  key: ValueKey<String>('assigned_job_${job.id}'),
                  job: job,
                  showAssignedTechnician: false,
                  showNextAction: true,
                  onTap: () => _openJob(context, job.id),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _openJob(BuildContext context, String jobId) {
    context.goNamed(
      'jobDetails',
      pathParameters: <String, String>{'id': jobId},
    );
  }
}

/// The one high-priority task surface. It carries the existing Start/Continue
/// route action without attempting to change job status from the dashboard.
class _FocusJobCard extends StatelessWidget {
  const _FocusJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);
    final Color accent = JobStatusBadge.styleFor(context, job.status).$1;
    final String? dateLabel = _dateLabel(context);
    final bool isAssigned = job.status.value == JobStatus.assigned;

    void open() => context.goNamed(
      'jobDetails',
      pathParameters: <String, String>{'id': job.id},
    );

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
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
                      if ((job.customerName ?? '').trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          job.customerName!.trim(),
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
                          _FocusMeta(
                            icon: job.jobType == JobCategory.kitchenRenovation
                                ? Icons.kitchen_outlined
                                : Icons.house_siding_outlined,
                            text: mapper.jobTypeLabel(job.jobType),
                          ),
                          if (dateLabel != null)
                            _FocusMeta(
                              icon: Icons.schedule_outlined,
                              text: dateLabel,
                            ),
                        ],
                      ),
                      if ((job.description ?? '').trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          job.description!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: Key(
                            isAssigned
                                ? 'start_job_${job.id}'
                                : 'continue_job_${job.id}',
                          ),
                          onPressed: open,
                          icon: Icon(
                            isAssigned
                                ? Icons.play_arrow_rounded
                                : Icons.arrow_forward_rounded,
                            size: AppDimensions.iconMd,
                          ),
                          label: Text(
                            isAssigned
                                ? l10n.startJobButton
                                : l10n.continueJobButton,
                          ),
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
    );
  }

  String? _dateLabel(BuildContext context) {
    final DateTime? date = job.startedAt ?? job.assignedAt;
    if (date == null) {
      return null;
    }
    final String prefix = job.startedAt != null
        ? context.l10n.startDateLabel
        : context.l10n.assignedDateLabel;
    return '$prefix: ${formatJobDate(date, context)}';
  }
}

class _FocusMeta extends StatelessWidget {
  const _FocusMeta({required this.icon, required this.text});

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

/// Category links are still available in every jobs state. Counts only render
/// from a successful local snapshot, never as invented zeros during a failure.
class _TechnicianCategories extends StatelessWidget {
  const _TechnicianCategories({this.jobs});

  final List<Job>? jobs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<Job>? snapshot = jobs;
    final int? kitchenCount = snapshot
        ?.where((Job job) => job.jobType == JobCategory.kitchenRenovation)
        .length;
    final int? homeCount = snapshot
        ?.where((Job job) => job.jobType == JobCategory.homeRenovation)
        .length;

    final Widget kitchen = DashboardCategoryCard(
      key: const Key('category_card_kitchen'),
      title: l10n.jobCategoryKitchenRenovation,
      icon: Icons.kitchen_outlined,
      jobCount: kitchenCount,
      countLabel: l10n.jobsCountLabel,
      semanticLabel:
          '${l10n.jobCategoryKitchenRenovation}'
          '${kitchenCount == null ? '' : ', ${l10n.jobsCountLabel(kitchenCount)}'}',
      isKitchen: true,
      onTap: () => context.go(
        '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}',
      ),
    );
    final Widget home = DashboardCategoryCard(
      key: const Key('category_card_home_renovation'),
      title: l10n.jobCategoryHomeRenovation,
      icon: Icons.house_siding_outlined,
      jobCount: homeCount,
      countLabel: l10n.jobsCountLabel,
      semanticLabel:
          '${l10n.jobCategoryHomeRenovation}'
          '${homeCount == null ? '' : ', ${l10n.jobsCountLabel(homeCount)}'}',
      isKitchen: false,
      onTap: () => context.go(
        '${AppRoutes.jobs}?category=${JobCategory.homeRenovation}',
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: l10n.categoriesTitle, showRule: false),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool useTwoColumns =
                constraints.maxWidth >= AppDimensions.tabletBreakpoint;

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

class _NoAssignedJobs extends StatelessWidget {
  const _NoAssignedJobs();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppSurfacePanel(
      key: const Key('tech_jobs_empty'),
      divideRows: false,
      children: <Widget>[
        AppEmptyStateView(
          icon: Icons.event_note_outlined,
          title: l10n.noAssignedJobsTitle,
          message: l10n.noAssignedJobsSubtitle,
          action: FilledButton.icon(
            onPressed: () => context.push(AppRoutes.jobTechnicianCreate),
            icon: const Icon(
              Icons.person_add_alt_1_outlined,
              size: AppDimensions.iconMd,
            ),
            label: Text(l10n.technicianCreateJobEntryTitle),
          ),
        ),
      ],
    );
  }
}

/// Which of two assigned jobs has waited longer for pickup.
Job _longerWaiting(Job a, Job b) {
  final DateTime? assignedA = a.assignedAt;
  final DateTime? assignedB = b.assignedAt;
  if (assignedA == null) {
    return b;
  }
  if (assignedB == null) {
    return a;
  }
  return assignedA.isBefore(assignedB) ? a : b;
}

/// Only rebuild job-dependent sections when their visible snapshot changes.
bool _jobsSnapshotChanged(JobsState previous, JobsState current) =>
    previous.status != current.status || !identical(previous.jobs, current.jobs);

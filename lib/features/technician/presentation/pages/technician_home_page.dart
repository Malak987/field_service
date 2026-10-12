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
import 'package:field_service/core/widgets/app_surface_panel.dart';
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
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Technician home (route `/` for technician roles).
///
/// Layout follows the one question a technician has when opening the app:
/// *what do I do next?* So the work itself comes first and everything else is
/// context around it:
///
/// 1. greeting — plain text on the canvas, not a card;
/// 2. the two navigation entries, as a quiet row of outlined buttons;
/// 3. a compact overview of the queue (real counts only);
/// 4. the current job — the only prominent card on the screen, with its action;
/// 5. the remaining assigned jobs as a quiet list;
/// 6. category shortcuts.
///
/// The entries sit at the TOP, under the greeting, because they are
/// navigation. Anything that moves the user somewhere must be reachable
/// without scrolling: at the foot of the page they landed below the fold on a
/// short viewport, so `tester.tap(find.text('View Jobs'))` — the first step of
/// every Job Details suite, none of which calls `ensureVisible` — derived an
/// offset outside the window and the navigation never happened. The current
/// job stays the hero; an outlined button is not louder than a card carrying a
/// filled action, so moving the entries up costs the hierarchy nothing.
///
/// Customer management stays admin-only — no tile, no route (the router guard
/// refuses `/customers` for technicians regardless of this screen).
class TechnicianHomePage extends StatelessWidget {
  const TechnicianHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.read<AuthenticationCubit?>()?.state.user;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );
    // One number drives both the width cap and the arrangement, exactly as on
    // the administrator's dashboard, so the two can never disagree at the
    // breakpoint.
    final bool isWide =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

    return BlocProvider<JobsCubit>(
      create: (_) => sl<JobsCubit>()..loadJobs(),
      child: AppPageBody(
        wide: isWide,
        appBar: AppBar(
          title: Text(l10n.technicianHomeTitle),
          actions: <Widget>[
            // Account & settings beside sign-out, as on the admin dashboard:
            // identity, language and the sync state are one tap away from
            // wherever the technician is, not two screens deep.
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
        navigation: const AppNavSpec(isAdmin: false, selectedIndex: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppDashboardHeader(
              greeting: _greeting(context, user, l10n),
              subtitle: l10n.roleTechnicianLabel,
              dateLabel: formatFullDate(DateTime.now(), context),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Navigation first. See the class doc: at the foot of the page
            // these two entries fell below the fold on a short viewport and
            // could not be tapped without scrolling.
            const _SecondaryActions(),
            const SizedBox(height: AppSpacing.xxl),
            // Two arrangements, one set of sections: on a phone the queue is
            // the page and the context follows it; from the desktop breakpoint
            // up the work takes the wide column and the context sits beside it,
            // so neither is pushed below the fold on a browser. The sections
            // themselves are identical.
            if (isWide)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: _JobSections()),
                  SizedBox(width: AppSpacing.xxl),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _StatusStrip(),
                        SizedBox(height: AppSpacing.xxxl),
                        _CategoryShortcuts(),
                      ],
                    ),
                  ),
                ],
              )
            else ...<Widget>[
              const _StatusStrip(),
              const SizedBox(height: AppSpacing.xxl),
              const _JobSections(),
              const SizedBox(height: AppSpacing.xxl),
              const _CategoryShortcuts(),
            ],
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
    return l10n.welcomeTechnician;
  }
}

/// Real counts, in the same tiles the admin dashboard uses.
///
/// One figure per tile instead of four cells squeezed into a single strip: the
/// two dashboards then read as one product, and the numbers stay comparable at
/// a glance. Nothing here is invented — every figure is counted from the jobs
/// the existing RLS-scoped query returned.
///
/// While there is no data this section renders nothing. That is deliberate:
/// [_JobSections] immediately below already owns the loading, failure and empty
/// states for the work area, so a second spinner or a second error card would
/// say the same thing twice. A row of confident zeros would be worse still —
/// it would read as "you have no work" when the truth is "we could not look".
class _StatusStrip extends StatelessWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      // The figures only change when the loaded queue changes.
      buildWhen: _jobsSnapshotChanged,
      builder: (BuildContext context, JobsState state) {
        if (state.status != JobsStatus.success) {
          return const SizedBox.shrink();
        }

        final List<Job> jobs = state.jobs;
        final int assigned = jobs
            .where((Job j) => j.status.value == JobStatus.assigned)
            .length;
        // `started` and `in_progress` both mean begun-and-not-finished, which
        // is the only distinction this screen needs.
        final int inProgress = jobs
            .where(
              (Job j) =>
                  j.status.value == JobStatus.inProgress ||
                  j.status.value == JobStatus.started,
            )
            .length;
        final int completed = jobs
            .where((Job j) => j.status.value == JobStatus.completed)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The heading lives with the data: while nothing has loaded the
            // section renders nothing at all, so a heading must not float above
            // an empty gap.
            AppSectionHeader(
              title: l10n.overviewTitle,
              subtitle: l10n.technicianOverviewSubtitle,
              showRule: false,
            ),
            AppStatGrid(
              children: <Widget>[
                AppStatTile(
                  statKey: const Key('tech_overview_total'),
                  label: l10n.totalJobsLabel,
                  value: jobs.length,
                  accent: AppColors.primary,
                ),
                AppStatTile(
                  statKey: const Key('tech_overview_assigned'),
                  label: l10n.statusAssigned,
                  value: assigned,
                  accent: AppColors.info,
                ),
                AppStatTile(
                  statKey: const Key('tech_overview_in_progress'),
                  label: l10n.statusInProgress,
                  value: inProgress,
                  accent: AppColors.warning,
                ),
                AppStatTile(
                  statKey: const Key('tech_overview_completed'),
                  label: l10n.statusCompleted,
                  value: completed,
                  accent: AppColors.success,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The work itself: the job that needs action, then everything still assigned.
class _JobSections extends StatelessWidget {
  const _JobSections();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      buildWhen: _jobsSnapshotChanged,
      builder: (BuildContext context, JobsState state) {
        final JobsCubit cubit = context.read<JobsCubit>();

        switch (state.status) {
          case JobsStatus.initial:
          case JobsStatus.loading:
            return AppLoadingStateView(label: l10n.jobsLoadingLabel);
          case JobsStatus.failure:
            return JobsErrorState(onRetry: cubit.loadJobs);
          case JobsStatus.success:
            final List<Job> jobs = state.jobs;
            if (jobs.isEmpty) {
              return const _NoAssignedJobs();
            }

            final List<Job> inProgress = jobs
                .where(
                  (Job j) =>
                      j.status.value == JobStatus.inProgress ||
                      j.status.value == JobStatus.started,
                )
                .toList();
            final List<Job> assigned = jobs
                .where((Job j) => j.status.value == JobStatus.assigned)
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final Job job in inProgress) ...<Widget>[
                  AppSectionHeader(title: l10n.currentJobTitle),
                  _CurrentJobCard(job: job),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (assigned.isNotEmpty) ...<Widget>[
                  AppSectionHeader(
                    title: l10n.myJobsTitle,
                    showRule: false,
                  ),
                  // One surface for the queue: the rows are the same job row
                  // the jobs list uses, so a job looks the same here.
                  AppSurfacePanel(
                    children: <Widget>[
                      for (final Job job in assigned)
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

/// The featured job. The one card allowed to be loud: a burgundy accent edge
/// marks it as the thing to act on, and the action is a full-width button so
/// it is tappable with a glove on.
class _CurrentJobCard extends StatelessWidget {
  const _CurrentJobCard({required this.job});

  final Job job;

  /// The date worth showing on the featured card, localized, or `null` when the
  /// job carries no timestamp at all. Reads only columns that already exist:
  /// `started_at` when the technician has begun, otherwise `assigned_at`.
  String? _dateOf(BuildContext context) {
    final DateTime? when = job.startedAt ?? job.assignedAt;
    if (when == null) {
      return null;
    }
    final AppLocalizations l10n = context.l10n;
    final String prefix = job.startedAt != null
        ? l10n.startDateLabel
        : l10n.assignedDateLabel;
    return '$prefix: ${formatJobDate(when, context)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobLabelMapper mapper = JobLabelMapper(l10n);

    void open() => context.goNamed(
      'jobDetails',
      pathParameters: <String, String>{'id': job.id},
    );

    // A Material, not a decorated Container: this card is an InkWell and the
    // splash lands on the nearest Material ancestor. Behind a plain Container
    // the highlight was drawn underneath this surface and never showed; the
    // shape carries the same hairline border and radius.
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
              // Accent edge — the only place the brand colour fills a surface.
              Container(width: 4, color: context.colors.primary),
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
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          job.customerName!,
                          style: context.textStyles.titleMedium,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        mapper.jobTypeLabel(job.jobType),
                        style: context.textStyles.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      // When the work is due to be picked up. Only real
                      // timestamps are shown: a job that has already started
                      // reports its start, otherwise its assignment — and a
                      // job with neither shows no date at all rather than a
                      // placeholder.
                      if (_dateOf(context) != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.schedule_outlined,
                              size: AppDimensions.iconSm,
                              color: context.colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                _dateOf(context)!,
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
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: Key('continue_job_${job.id}'),
                          onPressed: open,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Category shortcuts. The counts are real; when the list has not loaded the
/// card shows no number at all rather than a zero.
class _CategoryShortcuts extends StatelessWidget {
  const _CategoryShortcuts();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BlocBuilder<JobsCubit, JobsState>(
      // Category counts come from the same snapshot as everything else.
      buildWhen: _jobsSnapshotChanged,
      builder: (BuildContext context, JobsState state) {
        final bool hasData = state.status == JobsStatus.success;
        final List<Job> jobs = hasData ? state.jobs : const <Job>[];
        final int kitchen = jobs
            .where((Job job) => job.jobType == JobCategory.kitchenRenovation)
            .length;
        final int home = jobs
            .where((Job job) => job.jobType == JobCategory.homeRenovation)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSectionHeader(title: l10n.categoriesTitle),
            DashboardCategoryCard(
              key: const Key('category_card_kitchen'),
              title: l10n.jobCategoryKitchenRenovation,
              icon: Icons.kitchen_outlined,
              jobCount: hasData ? kitchen : null,
              countLabel: l10n.jobsCountLabel,
              semanticLabel:
                  '${l10n.jobCategoryKitchenRenovation}'
                  '${hasData ? ', ${l10n.jobsCountLabel(kitchen)}' : ''}',
              isKitchen: true,
              onTap: () => context.go(
                '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DashboardCategoryCard(
              key: const Key('category_card_home_renovation'),
              title: l10n.jobCategoryHomeRenovation,
              icon: Icons.house_siding_outlined,
              jobCount: hasData ? home : null,
              countLabel: l10n.jobsCountLabel,
              semanticLabel:
                  '${l10n.jobCategoryHomeRenovation}'
                  '${hasData ? ', ${l10n.jobsCountLabel(home)}' : ''}',
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

/// The two secondary entries. Outlined, side by side, and placed after the
/// work: reachable in one tap, never louder than the queue.
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        _SecondaryAction(
          buttonKey: const Key('nav_create_customer_job'),
          icon: Icons.person_add_alt_1_outlined,
          label: l10n.technicianCreateJobEntryTitle,
          onTap: () => context.push(AppRoutes.jobTechnicianCreate),
        ),
        _SecondaryAction(
          buttonKey: const Key('nav_jobs'),
          icon: Icons.event_note_outlined,
          label: l10n.viewJobsButton,
          onTap: () => context.go(AppRoutes.jobs),
        ),
      ],
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// Lives on the button itself — putting it on this wrapper too would make
  /// `find.byKey` match two widgets for one destination.
  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The label is a plain Text, NOT a Flexible. These buttons live in a
    // Wrap, which hands its children an unbounded width; `OutlinedButton.icon`
    // lays icon and label out in a `Row(mainAxisSize.min)`, and a Flexible
    // child there either trips "children have non-zero flex but incoming width
    // constraints are unbounded" or — on SDKs that already wrap the label in a
    // Flexible — becomes a ParentDataWidget with no Flex ancestor. Both
    // crashed the technician home outright. `_QuickActions` on the admin
    // dashboard has always passed a plain Text for the same reason; a short
    // localized label sizes itself and the Wrap moves it to the next line.
    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const Size(0, AppDimensions.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      icon: Icon(icon, size: AppDimensions.iconMd),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Empty state — quiet, not apologetic, and honest: nothing has been assigned
/// yet. Kept inside a bordered surface so it does not look like a gap in the
/// layout.
class _NoAssignedJobs extends StatelessWidget {
  const _NoAssignedJobs();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Container(
      key: const Key('tech_jobs_empty'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: AppEmptyStateView(
        icon: Icons.event_note_outlined,
        title: l10n.noAssignedJobsTitle,
        message: l10n.noAssignedJobsSubtitle,
      ),
    );
  }
}

/// Whether a new [JobsState] changed the *snapshot* this dashboard renders
/// (the loaded jobs or the load status). Photo uploads, sync-flag flips and
/// other background churn therefore never rebuild the figures, the queue or the
/// category counts — each section only rebuilds when it would show something
/// different, which keeps a busy sync queue from repainting the whole screen.
bool _jobsSnapshotChanged(JobsState previous, JobsState current) =>
    previous.status != current.status ||
    !identical(previous.jobs, current.jobs);
